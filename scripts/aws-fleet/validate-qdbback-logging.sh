#!/usr/bin/env bash
# validate-qdbback-logging.sh — Fase 3: probe externo + verifica INSERT SQLite
#
# Uso:
#   ./scripts/aws-fleet/validate-qdbback-logging.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

HOST="${HOST:-3.236.249.77}"
SSH_ALIAS="${SSH_ALIAS:-aws-ec2-fleet-01}"
PROBE_PATH="/qdbback-smoke-$(date +%s)"

log "Contagem antes do probe..."
BEFORE="$(ssh -o BatchMode=yes "$SSH_ALIAS" \
  "python3 -c \"import sqlite3;c=sqlite3.connect('/home/ec2-user/database.sqlite');print(c.execute('SELECT COUNT(*) FROM httpRequests').fetchone()[0])\"")"

log "Probe externo: http://${HOST}${PROBE_PATH}"
HTTP_CODE="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 "http://${HOST}${PROBE_PATH}" || echo "000")"
log "HTTP response: $HTTP_CODE"

sleep 2

AFTER="$(ssh -o BatchMode=yes "$SSH_ALIAS" \
  "python3 -c \"import sqlite3;c=sqlite3.connect('/home/ec2-user/database.sqlite');print(c.execute('SELECT COUNT(*) FROM httpRequests').fetchone()[0])\"")"

log "httpRequests: $BEFORE → $AFTER"

if [[ "$HTTP_CODE" == "000" ]]; then
  fail "Probe externo falhou — verifique SG (Fase 2) e se qdbback está rodando"
fi

if [[ "$AFTER" -le "$BEFORE" ]]; then
  fail "SQLite não incrementou — logging end-to-end falhou"
fi

log "✅ Fase 3 OK — logging end-to-end confirmado (+$((AFTER - BEFORE)) request)"
