#!/usr/bin/env bash
# ssh_harden_ssdnodes.sh — Endurece sshd (key-only, no password root login).
# T-320a / Fleet Copilot gate. Verifica authorized_keys antes de aplicar.
#
# Uso:
#   ssh_harden_ssdnodes.sh [--host ssdnodes-6a12f10c9ef11] [--dry-run|--apply]

set -euo pipefail

TARGET_HOST="ssdnodes-6a12f10c9ef11"
ACTION="dry-run"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)    TARGET_HOST="$2"; shift 2 ;;
        --dry-run) ACTION="dry-run"; shift ;;
        --apply)   ACTION="apply"; shift ;;
        -h|--help)
            echo "Uso: $0 [--host HOST] [--dry-run|--apply]"
            exit 0
            ;;
        *) echo "Opção desconhecida: $1"; exit 1 ;;
    esac
done

_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=no)

_run() {
    "${_SSH[@]}" "$TARGET_HOST" "sudo bash -s" <<REMOTE
set -euo pipefail
ACTION="$ACTION"

for u in root \$(getent passwd | awk -F: '\$3 >= 1000 && \$3 < 65534 {print \$1}'); do
    home=\$(getent passwd "\$u" | cut -d: -f6)
    if [[ -s "\${home}/.ssh/authorized_keys" ]]; then
        echo "OK: \$u has authorized_keys"
    else
        echo "WARN: \$u has no authorized_keys — review before disabling passwords"
    fi
done

DROPIN="/etc/ssh/sshd_config.d/99-fleet-copilot-hardening.conf"
CONTENT='# Fleet Copilot / T-320a — SSH hardening
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
MaxAuthTries 4
X11Forwarding no
AllowAgentForwarding no
'

if [[ "\$ACTION" == "dry-run" ]]; then
    echo "=== DRY RUN: would write \$DROPIN ==="
    echo "\$CONTENT"
    sshd -t 2>/dev/null && echo "sshd -t: OK (current config)"
    exit 0
fi

echo "\$CONTENT" > "\$DROPIN"
chmod 644 "\$DROPIN"

# cloud-init often re-enables password auth — override drop-in wins if loaded last
if [[ -f /etc/ssh/sshd_config.d/50-cloud-init.conf ]]; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config.d/50-cloud-init.conf || true
fi

sshd -t
systemctl reload sshd
echo "OK: sshd reloaded with hardening drop-in"
sshd -T | grep -E 'passwordauthentication|permitrootlogin|maxauthtries'
REMOTE
}

_run
