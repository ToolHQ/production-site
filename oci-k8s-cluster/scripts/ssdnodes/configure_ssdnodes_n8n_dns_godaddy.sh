#!/usr/bin/env bash
# configure_ssdnodes_n8n_dns_godaddy.sh — A record n8n.ssdnodes via GoDaddy API (T-361)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
QDBBACK_SCRIPT="$REPO_ROOT/scripts/aws-fleet/configure-qdbback-dns-godaddy.sh"

ZONE="${GODADDY_ZONE:-dnor.io}"
TARGET_IP="${SSD_NODES_IP:-104.225.218.78}"
DRY_RUN=false
ENV_FILE="${GODADDY_ENV_FILE:-$REPO_ROOT/.env.godaddy}"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=true; shift ;;
  -h | --help)
    echo "Uso: $0 [--dry-run]  — cria n8n.ssdnodes.${ZONE} → ${TARGET_IP}"
    exit 0
    ;;
  *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

[[ -x "$QDBBACK_SCRIPT" ]] || {
  echo "❌ script base ausente: $QDBBACK_SCRIPT" >&2
  exit 1
}

extra=()
[[ "$DRY_RUN" == true ]] && extra+=(--dry-run)

echo "=== n8n.ssdnodes.${ZONE} → ${TARGET_IP} ==="
GODADDY_HOST="n8n.ssdnodes" QDBBACK_TARGET_IP="$TARGET_IP" GODADDY_ENV_FILE="$ENV_FILE" \
  bash "$QDBBACK_SCRIPT" "${extra[@]}"

echo "✓ DNS n8n — valide: dig +short n8n.ssdnodes.${ZONE} @ns75.domaincontrol.com"
