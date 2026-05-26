#!/usr/bin/env bash
# configure-qdbback-dns-godaddy.sh — A record honeypot.dnor.io via GoDaddy API
#
# Uso:
#   source .env.godaddy   # GODADDY_API_KEY + GODADDY_API_SECRET
#   ./scripts/aws-fleet/configure-qdbback-dns-godaddy.sh
#   ./scripts/aws-fleet/configure-qdbback-dns-godaddy.sh --dry-run
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DOMAIN="${QDBBACK_TLS_DOMAIN:-honeypot.dnor.io}"
ZONE="${GODADDY_ZONE:-dnor.io}"
HOST="${GODADDY_HOST:-honeypot}"
TARGET_IP="${QDBBACK_TARGET_IP:-3.236.249.77}"
TTL="${GODADDY_TTL:-600}"
DRY_RUN=false
ENV_FILE="${GODADDY_ENV_FILE:-$REPO_ROOT/.env.godaddy}"

usage() {
  cat <<'EOF'
Cria/atualiza registro A no GoDaddy para o honeypot qdbback.

Variáveis:
  GODADDY_API_KEY / GODADDY_API_SECRET  (obrigatório)
  QDBBACK_TLS_DOMAIN  default: honeypot.dnor.io
  QDBBACK_TARGET_IP   default: 3.236.249.77
  GODADDY_ENV_FILE    default: .env.godaddy na raiz do repo

Opções:
  --dry-run
  --env-file PATH
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Argumento desconhecido: $1" ;;
  esac
done

if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a
fi

[[ -n "${GODADDY_API_KEY:-}" && -n "${GODADDY_API_SECRET:-}" ]] \
  || fail "Defina GODADDY_API_KEY e GODADDY_API_SECRET (ex.: source .env.godaddy)"

info "GoDaddy A record: ${HOST}.${ZONE} → ${TARGET_IP} (TTL ${TTL})"

if [[ "$DRY_RUN" == true ]]; then
  info "[dry-run] PUT /v1/domains/${ZONE}/records/A/${HOST}"
  exit 0
fi

http_code="$(curl -sS -o /tmp/godaddy-dns-response.txt -w '%{http_code}' -X PUT \
  -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}" \
  -H "Content-Type: application/json" \
  "https://api.godaddy.com/v1/domains/${ZONE}/records/A/${HOST}" \
  -d "[{\"data\":\"${TARGET_IP}\",\"ttl\":${TTL}}]")"

if [[ "$http_code" != "200" ]]; then
  cat /tmp/godaddy-dns-response.txt >&2
  fail "GoDaddy API HTTP ${http_code}"
fi

ok "DNS atualizado — valide: ./scripts/aws-fleet/deploy-qdbback-ec2.sh --phase dns-check"
