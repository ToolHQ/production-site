#!/usr/bin/env bash
# configure_ssdnodes_ci_dns_godaddy.sh — A records sonar + jenkins via GoDaddy API (T-341)
#
# Uso:
#   source .env.godaddy
#   ./oci-k8s-cluster/scripts/ssdnodes/configure_ssdnodes_ci_dns_godaddy.sh
#   ./oci-k8s-cluster/scripts/ssdnodes/configure_ssdnodes_ci_dns_godaddy.sh --dry-run
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
QDBBACK_SCRIPT="$REPO_ROOT/scripts/aws-fleet/configure-qdbback-dns-godaddy.sh"

ZONE="${GODADDY_ZONE:-dnor.io}"
TARGET_IP="${SSD_NODES_IP:-104.225.218.78}"
DRY_RUN=false
ENV_FILE="${GODADDY_ENV_FILE:-$REPO_ROOT/.env.godaddy}"

usage() {
  cat <<EOF
Cria/atualiza registros A no GoDaddy para CI Platform SSDNodes:
  - sonar.ssdnodes.${ZONE}
  - jenkins.ssdnodes.${ZONE}

Variáveis:
  GODADDY_API_KEY / GODADDY_API_SECRET  (obrigatório — .env.godaddy)
  SSD_NODES_IP   default: 104.225.218.78
  GODADDY_ENV_FILE

Opções:
  --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=true; shift ;;
  -h | --help) usage; exit 0 ;;
  *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

[[ -x "$QDBBACK_SCRIPT" ]] || {
  echo "❌ script base ausente: $QDBBACK_SCRIPT" >&2
  exit 1
}

for host in sonar.ssdnodes jenkins.ssdnodes; do
  echo "=== ${host}.${ZONE} → ${TARGET_IP} ==="
  extra=()
  [[ "$DRY_RUN" == true ]] && extra+=(--dry-run)
  GODADDY_HOST="$host" QDBBACK_TARGET_IP="$TARGET_IP" GODADDY_ENV_FILE="$ENV_FILE" \
    bash "$QDBBACK_SCRIPT" "${extra[@]}"
done

echo "✓ DNS CI configurado — valide: dig +short sonar.ssdnodes.${ZONE} @ns75.domaincontrol.com"
