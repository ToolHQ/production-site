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
run_ssh bash <<REMOTE
set -eo pipefail
QDBBACK_DB_PATH=/home/ec2-user/database.sqlite QDBBACK_LOGS_KEEP_DAYS=${LOGS_KEEP_DAYS} \
  /home/ec2-user/.nvm/versions/node/v16.20.2/bin/node /home/ec2-user/server/scripts/purge-old-data.js
REMOTE
