#!/usr/bin/env bash
# provision-aws-external-node.sh — Bootstrap seguro + registro no Node Fleet (reutilizável)
#
# Uso:
#   ./scripts/aws-fleet/provision-aws-external-node.sh \
#     --host 3.236.249.77 \
#     --instance-id i-0e8ca7a9b50e474a9 \
#     --name aws-ec2-fleet-01 \
#     --role dedicated \
#     --ssh-user root \
#     --apply
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

HOST=""
INSTANCE_ID=""
NODE_ID=""
ROLE="dedicated"
SSH_USER="root"
SSH_ALIAS=""
DRY_RUN=false
SKIP_BOOTSTRAP=false
SKIP_APPLY=false
SKIP_GENERATE=false
OPERATOR_IP=""
APPLY_K8S=false

usage() {
  cat <<'EOF'
Provisiona uma instância AWS/EC2 como nó externo monitorado no Node Fleet.

Obrigatório:
  --host IP_PUBLICO
  --instance-id i-xxxxxxxx
  --name NOME_CURTO          (ex: aws-ec2-fleet-01)

Opcional:
  --role dedicated|builder   (default: dedicated)
  --ssh-user root            (usuário inicial com acesso SSH)
  --ssh-alias ALIAS          (default: mesmo --name)
  --operator-ip IP           (default: IP público detectado)
  --dry-run                  (mostra plano, não altera)
  --skip-bootstrap           (nó já bootstrapped)
  --skip-generate            (não regenera artefatos)
  --apply                    (kubectl apply nos manifests gerados)

Fluxo:
  1. Gera par de chaves ed25519 (~/.ssh/aws-fleet-<name>.ed25519)
  2. Bootstrap remoto idempotente (ops user, node-exporter, UFW, ssh hardening)
  3. Registra nó em config/external-fleet/registry.yaml
  4. Regenera manifests K8s, external_nodes.json, common.sh, harness, CSS
  5. (--apply) kubectl apply + smoke SSH/exporter

Requisitos locais:
  python3, PyYAML, curl, ssh, kubectl (se --apply)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --instance-id) INSTANCE_ID="$2"; shift 2 ;;
    --name) NODE_ID="$2"; shift 2 ;;
    --role) ROLE="$2"; shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --ssh-alias) SSH_ALIAS="$2"; shift 2 ;;
    --operator-ip) OPERATOR_IP="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --skip-bootstrap) SKIP_BOOTSTRAP=true; shift ;;
    --skip-generate) SKIP_GENERATE=true; shift ;;
    --apply) APPLY_K8S=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Argumento desconhecido: $1" ;;
  esac
done

[[ -n "$HOST" ]] || fail "--host é obrigatório"
[[ -n "$INSTANCE_ID" ]] || fail "--instance-id é obrigatório"
[[ -n "$NODE_ID" ]] || fail "--name é obrigatório"
SSH_ALIAS="${SSH_ALIAS:-$NODE_ID}"

if registry_has_node "$HOST" 2>/dev/null; then
  warn "Host $HOST já está no registry — use generate ou edite manualmente"
fi

mapfile -t DEFAULTS < <(read_registry_defaults)
OPS_USER="${DEFAULTS[0]:-dnorio-fleet}"
METRICS_PORT="${DEFAULTS[1]:-9100}"

if [[ -z "$OPERATOR_IP" ]]; then
  OPERATOR_IP="$(detect_operator_public_ip || true)"
fi

OCI_IPS="$(python3 - "$REGISTRY_PATH" <<'PY'
import yaml, sys
data = yaml.safe_load(open(sys.argv[1]))
print(",".join(data.get("scrape_sources", {}).get("oci_k8s_public_ips", [])))
PY
)"

KEY_FILE="$(expand_path "~/.ssh/aws-fleet-${NODE_ID}.ed25519")"
PUB_FILE="${KEY_FILE}.pub"

info "Plano de provisionamento"
echo "  host .............. $HOST"
echo "  instance-id ....... $INSTANCE_ID"
echo "  node-id ........... $NODE_ID"
echo "  ssh-alias ......... $SSH_ALIAS"
echo "  ops-user .......... $OPS_USER"
echo "  operator-ip ....... ${OPERATOR_IP:-<não detectado>}"
echo "  oci-scrape-ips .... $OCI_IPS"
echo "  key ............... $KEY_FILE"

if $DRY_RUN; then
  ok "Dry-run — nenhuma alteração aplicada"
  exit 0
fi

require_cmd ssh-keygen
require_cmd ssh
require_cmd scp
require_cmd python3
require_cmd curl

if [[ ! -f "$KEY_FILE" ]]; then
  info "Gerando chave SSH dedicada"
  ssh-keygen -t ed25519 -f "$KEY_FILE" -C "${OPS_USER}@${NODE_ID}@production-site" -N ""
  chmod 600 "$KEY_FILE"
  ok "Chave criada: $KEY_FILE"
else
  ok "Reutilizando chave existente: $KEY_FILE"
fi

REMOTE="${SSH_USER}@${HOST}"
METADATA_JSON="/tmp/aws-fleet-${NODE_ID}-metadata.json"
REGISTRY_PAYLOAD="/tmp/aws-fleet-${NODE_ID}-registry.json"

if ! $SKIP_BOOTSTRAP; then
  info "Testando SSH inicial ($REMOTE)"
  if ! ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new "$REMOTE" "echo connected-as-\$(whoami)"; then
    fail "SSH falhou para $REMOTE — libere :22 para seu IP no Security Group e garanta acesso root por chave/senha"
  fi

  info "Enviando remote-bootstrap.sh"
  scp -o StrictHostKeyChecking=accept-new "$REMOTE_BOOTSTRAP" "${REMOTE}:/tmp/aws-fleet-remote-bootstrap.sh"

  scp "$PUB_FILE" "${REMOTE}:/tmp/aws-fleet-bootstrap.pub"
  info "Executando bootstrap remoto (idempotente)"
  ssh "$REMOTE" "sudo OPS_USER='$OPS_USER' METRICS_PORT='$METRICS_PORT' OPERATOR_SSH_IP='$OPERATOR_IP' OCI_SCRAPE_IPS_CSV='$OCI_IPS' METADATA_OUT='/tmp/aws-fleet-metadata.json' bash /tmp/aws-fleet-remote-bootstrap.sh /tmp/aws-fleet-bootstrap.pub"
  scp "${REMOTE}:/tmp/aws-fleet-metadata.json" "$METADATA_JSON"

  ok "Bootstrap remoto concluído"
else
  warn "Bootstrap pulado (--skip-bootstrap)"
  ssh "${OPS_USER}@${HOST}" "curl -fsS http://127.0.0.1:${METRICS_PORT}/metrics | head -1" >/dev/null || \
    fail "node-exporter inacessível na instância"
  ssh "${OPS_USER}@${HOST}" "python3 - <<'PY'
import json, subprocess
def run(c):
    return subprocess.check_output(c, shell=True, text=True).strip()
print(json.dumps({'hostname': run('hostname'), 'cpu_millicores': int(run('nproc'))*1000}))
PY" > "$METADATA_JSON" || echo '{}' > "$METADATA_JSON"
fi

ensure_ssh_config_block "$SSH_ALIAS" "$HOST" "$OPS_USER" "$KEY_FILE"

info "Montando payload do registry"
python3 - "$REGISTRY_PAYLOAD" "$METADATA_JSON" "$NODE_ID" "$HOST" "$INSTANCE_ID" "$SSH_ALIAS" "$ROLE" <<'PY'
import json, sys
out, meta_path, node_id, host, instance_id, ssh_alias, role = sys.argv[1:8]
with open(meta_path) as f:
    meta = json.load(f)

fallback = meta.get("hostname") or node_id
payload = {
    "id": node_id,
    "provider": "aws",
    "instance_host": host,
    "instance_id": instance_id,
    "fallback_name": fallback,
    "ssh_alias": ssh_alias,
    "cluster": "AWS-EC2",
    "role": role,
    "cpu_millicores": int(meta.get("cpu_millicores") or 2000),
    "memory_bytes": int(meta.get("memory_bytes") or 0) or 4 * 1024**3,
    "ephemeral_storage_bytes": int(meta.get("ephemeral_storage_bytes") or 0) or 30 * 1024**3,
    "exporter_service": f"{node_id.replace('_', '-')}-node-exporter",
    "bootstrap_managed": True,
    "aws_instance_type": meta.get("aws_instance_type") or "",
    "aws_region": meta.get("aws_region") or "",
}
with open(out, "w") as f:
    json.dump(payload, f, indent=2)
print(json.dumps(payload, indent=2))
PY

if ! registry_has_node "$HOST" 2>/dev/null; then
  append_registry_node "$REGISTRY_PAYLOAD"
  ok "Nó registrado em $REGISTRY_PATH"
else
  warn "Host já registrado — pulando append"
fi

if ! $SKIP_GENERATE; then
  run_generator
fi

info "Smoke test via alias $SSH_ALIAS"
verify_remote_exporter "$SSH_ALIAS"
ok "node-exporter OK via $SSH_ALIAS"

if $APPLY_K8S; then
  if [[ -f "$REPO_ROOT/oci-k8s-cluster/scripts/setup-dev-deploy.sh" ]]; then
    # shellcheck disable=SC1091
    source "$REPO_ROOT/oci-k8s-cluster/scripts/setup-dev-deploy.sh" >/dev/null 2>&1 || true
  fi
  export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
  apply_k8s_manifests
  verify_prometheus_target "$HOST"
fi

cat <<EOF

╔══════════════════════════════════════════════════════════════╗
║  AWS External Node — provisionamento concluído               ║
╠══════════════════════════════════════════════════════════════╣
║  SSH .............. ssh $SSH_ALIAS                           ║
║  Metrics .......... http://${HOST}:${METRICS_PORT}/metrics   ║
║  Registry ......... config/external-fleet/registry.yaml      ║
╠══════════════════════════════════════════════════════════════╣
║  Próximos passos:                                            ║
║  1. Confirme Security Group AWS (:9100 só IPs OCI, :22 ops)  ║
║  2. cd apps/rs-observability-api && ./deploy.sh              ║
║  3. curl https://reports.dnor.io/api/live/overview           ║
╚══════════════════════════════════════════════════════════════╝

EOF
