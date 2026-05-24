#!/usr/bin/env bash
# pull-ec2-backup.sh — Baixa backup completo do home da EC2 aws-ec2-fleet-01
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEST="${REPO_ROOT}/archive/aws-ec2-fleet-01/recovery-$(date +%Y-%m-%d)"
SSH_HOST="${SSH_HOST:-aws-ec2-fleet-01}"
KEY="${KEY:-$HOME/.ssh/aws-fleet-aws-ec2-fleet-01.ed25519}"

mkdir -p "$DEST"

echo "[pull-ec2-backup] origem=$SSH_HOST dest=$DEST"

rsync -avz --info=progress2 \
  -e "ssh -i $KEY -o IdentitiesOnly=yes" \
  --exclude '.vscode-server/' \
  --exclude '.cache/' \
  "ec2-user@3.236.249.77:/home/ec2-user/" \
  "$DEST/"

if [[ -f "$DEST/database.sqlite" ]]; then
  sha256sum "$DEST/database.sqlite" | tee "$(dirname "$DEST")/checksums.sha256"
fi

echo "[ok] backup em $DEST"
