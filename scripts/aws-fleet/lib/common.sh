#!/usr/bin/env bash
# shellcheck disable=SC2034
# Biblioteca compartilhada — scripts/aws-fleet/*
set -euo pipefail

AWS_FLEET_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_FLEET_SCRIPT_DIR="$(cd "$AWS_FLEET_LIB_DIR/.." && pwd)"
REPO_ROOT="$(cd "$AWS_FLEET_SCRIPT_DIR/../.." && pwd)"

REGISTRY_PATH="$REPO_ROOT/config/external-fleet/registry.yaml"
GENERATOR="$AWS_FLEET_SCRIPT_DIR/generate_fleet_artifacts.py"
REMOTE_BOOTSTRAP="$AWS_FLEET_SCRIPT_DIR/remote-bootstrap.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${CYAN}[aws-fleet]${NC} $*"; }
ok()   { echo -e "${GREEN}[  ok ]${NC} $*"; }
warn() { echo -e "${YELLOW}[ warn ]${NC} $*"; }
fail() { echo -e "${RED}[ fail ]${NC} $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Comando obrigatório ausente: $1"
}

expand_path() {
  local p="$1"
  p="${p/#\~/$HOME}"
  printf '%s' "$p"
}

detect_operator_public_ip() {
  local ip=""
  for url in https://api.ipify.org https://ifconfig.me/ip; do
    ip="$(curl -fsS --max-time 8 "$url" 2>/dev/null || true)"
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      printf '%s' "$ip"
      return 0
    fi
  done
  return 1
}

read_registry_defaults() {
  python3 - "$REGISTRY_PATH" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
defaults = data.get("defaults", {})
print(defaults.get("ops_user", "dnorio-fleet"))
print(defaults.get("metrics_port", 9100))
PY
}

registry_has_node() {
  local host="$1"
  python3 - "$REGISTRY_PATH" "$host" <<'PY'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
host = sys.argv[2]
for node in data.get("nodes", []):
    if node.get("instance_host") == host:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

append_registry_node() {
  local json_file="$1"
  python3 - "$REGISTRY_PATH" "$json_file" <<'PY'
import json, sys, yaml

registry_path, payload_path = sys.argv[1], sys.argv[2]
with open(registry_path) as f:
    data = yaml.safe_load(f)
with open(payload_path) as f:
    node = json.load(f)

nodes = data.setdefault("nodes", [])
for existing in nodes:
    if existing.get("id") == node["id"] or existing.get("instance_host") == node["instance_host"]:
        raise SystemExit(f"Nó já registrado: id={node['id']} host={node['instance_host']}")

nodes.append(node)
with open(registry_path, "w") as f:
    yaml.safe_dump(data, f, sort_keys=False, allow_unicode=True)
PY
}

run_generator() {
  require_cmd python3
  info "Regenerando artefatos a partir de $REGISTRY_PATH"
  python3 "$GENERATOR" --registry "$REGISTRY_PATH" --repo-root "$REPO_ROOT"
  ok "Artefatos regenerados"
}

ensure_ssh_config_block() {
  local alias="$1"
  local host="$2"
  local user="$3"
  local key_file="$4"
  local ssh_config="$HOME/.ssh/config"
  local marker_begin="# BEGIN aws-fleet:${alias}"
  local marker_end="# END aws-fleet:${alias}"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$ssh_config"
  chmod 600 "$ssh_config"

  if grep -Fq "$marker_begin" "$ssh_config"; then
    ok "Bloco SSH já existe para $alias"
    return 0
  fi

  cat >>"$ssh_config" <<EOF

$marker_begin
Host $alias
  HostName $host
  User $user
  IdentityFile $key_file
  IdentitiesOnly yes
$marker_end
EOF
  ok "Entrada SSH adicionada: Host $alias"
}

apply_k8s_manifests() {
  require_cmd kubectl
  local dir="$REPO_ROOT/components/observability/external-fleet/generated"
  if [[ ! -d "$dir" ]]; then
    fail "Diretório de manifests ausente: $dir (rode generate primeiro)"
  fi
  for manifest in "$dir"/*-exporter.yaml; do
    [[ -f "$manifest" ]] || continue
    info "kubectl apply -f $manifest"
    kubectl apply -f "$manifest"
  done
  ok "Manifests Prometheus aplicados no cluster"
}

verify_remote_exporter() {
  local ssh_target="$1"
  ssh -o ConnectTimeout=10 -o BatchMode=yes "$ssh_target" \
    "curl -fsS http://127.0.0.1:9100/metrics | head -1"
}

verify_prometheus_target() {
  local host="$1"
  require_cmd kubectl
  info "Validando scrape Prometheus para $host (best-effort via port-forward omitido)"
  warn "Após apply, confira target UP em Coroot Prometheus UI ou /api/live/overview"
}
