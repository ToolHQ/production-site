#!/usr/bin/env bash
# validate-qdbback-metrics.sh — smoke /internal/metrics (T-302 Fase A)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

HOST="${QDBBACK_HOST:-3.236.249.77}"
SSH_ALIAS="${SSH_ALIAS:-oci-k8s-node-1}"

info "Off-cluster scrape (esperado 403)…"
off_body="$(curl -sk --max-time 15 "https://${HOST}/internal/metrics" || true)"
if [[ "$off_body" == *forbidden* ]]; then
  ok "403 forbidden off-cluster"
else
  fail "Esperado 403/forbidden; recebido: ${off_body:0:120}"
fi

info "OCI allowlisted scrape via ${SSH_ALIAS}…"
oci_body="$(ssh -o BatchMode=yes -o ConnectTimeout=15 "$SSH_ALIAS" \
  "curl -sk --max-time 15 https://${HOST}/internal/metrics" 2>/dev/null | head -5 || true)"
if [[ "$oci_body" == *qdbback_http_requests_total* ]]; then
  ok "Métricas Prometheus OK"
  echo "$oci_body"
else
  fail "Scrape OCI falhou: ${oci_body:0:200}"
fi

ok "validate-qdbback-metrics concluído"
