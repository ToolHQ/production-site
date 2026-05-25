#!/usr/bin/env bash
# purge-qdbback-db.sh — Purge applicationLogs antigos na EC2 (Fase 5c)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SSH_ALIAS="${SSH_ALIAS:-aws-ec2-fleet-01}"
LOGS_KEEP_DAYS="${QDBBACK_LOGS_KEEP_DAYS:-30}"

run_ssh() {
  ssh -o BatchMode=yes "$SSH_ALIAS" "$@"
}

info "Purge qdbback DB (applicationLogs > ${LOGS_KEEP_DAYS}d)"
run_ssh "QDBBACK_DB_PATH=/home/ec2-user/database.sqlite QDBBACK_LOGS_KEEP_DAYS=${LOGS_KEEP_DAYS} \
  /home/ec2-user/.nvm/versions/node/v22.*/bin/node /home/ec2-user/server/scripts/purge-old-data.js 2>/dev/null || \
  bash -lc 'export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 16.20.2 >/dev/null && QDBBACK_DB_PATH=/home/ec2-user/database.sqlite QDBBACK_LOGS_KEEP_DAYS=${LOGS_KEEP_DAYS} node /home/ec2-user/server/scripts/purge-old-data.js'
