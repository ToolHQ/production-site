#!/usr/bin/env bash
# install_ssdnodes_ssh_config.sh — merge T-331 SSH config + known_hosts for canonical hostname.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ssdnodes_host.sh
source "$SCRIPT_DIR/ssdnodes_host.sh"

SNIPPET="$SCRIPT_DIR/../../../components/ssdnodes/ssh-config.snippet"
SSH_CONFIG="${SSH_CONFIG:-$HOME/.ssh/config}"
MARKER="# BEGIN production-site ssdnodes (T-331)"
MARK_END="# END production-site ssdnodes (T-331)"

usage() {
  echo "Uso: $0 [--dry-run]"
  exit 0
}

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"

if grep -qF "$MARKER" "$SSH_CONFIG" 2>/dev/null; then
  echo "OK: bloco T-331 já presente em $SSH_CONFIG"
else
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "[dry-run] acrescentaria bloco de $SNIPPET em $SSH_CONFIG"
  else
    {
      echo ""
      echo "$MARKER"
      grep -v '^#' "$SNIPPET" | sed '/^[[:space:]]*$/d'
      echo "$MARK_END"
    } >>"$SSH_CONFIG"
    echo "OK: bloco T-331 adicionado em $SSH_CONFIG"
  fi
fi

if [[ "$DRY_RUN" == 1 ]]; then
  echo "[dry-run] ssh-keyscan $SSD_NODES_PUBLIC_IP"
  exit 0
fi

ssh-keyscan -H "$SSD_NODES_PUBLIC_IP" 2>/dev/null >>"$HOME/.ssh/known_hosts" || true
chmod 600 "$HOME/.ssh/known_hosts" 2>/dev/null || true

if ssh -o BatchMode=yes -o ConnectTimeout=12 "$SSD_NODES_CANONICAL_HOST" "hostname -f" 2>/dev/null | grep -q "$SSD_NODES_CANONICAL_HOST"; then
  echo "OK: ssh $SSD_NODES_CANONICAL_HOST hostname -f"
else
  echo "AVISO: ssh $SSD_NODES_CANONICAL_HOST falhou — ajuste IdentityFile em $SSH_CONFIG (copie de Host ssdnodes-monstro se existir)" >&2
  exit 1
fi
