#!/usr/bin/env bash
# fail2ban_ssdnodes.sh — Instala/configura fail2ban (jail sshd) em hosts gerenciados.
# Parte do gate T-320a (Fleet Copilot security prerequisites).
#
# Uso:
#   fail2ban_ssdnodes.sh [--host ssdnodes-6a12f10c9ef11] [--status|--apply]

set -euo pipefail

TARGET_HOST="ssdnodes-6a12f10c9ef11"
ACTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)   TARGET_HOST="$2"; shift 2 ;;
        --status) ACTION="status"; shift ;;
        --apply)  ACTION="apply"; shift ;;
        -h|--help)
            echo "Uso: $0 [--host HOST] [--status|--apply]"
            exit 0
            ;;
        *) echo "Opção desconhecida: $1"; exit 1 ;;
    esac
done

_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=no)

_remote_status() {
    "${_SSH[@]}" "$TARGET_HOST" 'bash -s' <<'REMOTE'
if ! command -v fail2ban-client &>/dev/null; then
    echo "fail2ban: NOT INSTALLED"
    exit 0
fi
echo "=== fail2ban status ==="
sudo fail2ban-client status 2>/dev/null || true
echo ""
echo "=== sshd jail ==="
sudo fail2ban-client status sshd 2>/dev/null || echo "sshd jail missing"
REMOTE
}

_remote_apply() {
    "${_SSH[@]}" "$TARGET_HOST" 'sudo bash -s' <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if ! command -v fail2ban-client &>/dev/null; then
    apt-get update -qq
    apt-get install -y -qq fail2ban
fi

mkdir -p /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/ssdnodes-sshd.local <<'JAIL'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
maxretry = 5
bantime  = 24h
findtime = 10m
JAIL

systemctl enable fail2ban
systemctl restart fail2ban
sleep 2
fail2ban-client status sshd
echo "OK: fail2ban sshd jail active"
REMOTE
}

case "${ACTION:-}" in
    status) _remote_status ;;
    apply)  _remote_apply ;;
    *)
        echo "Especifique --status ou --apply"
        exit 1
        ;;
esac
