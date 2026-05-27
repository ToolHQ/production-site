#!/bin/bash
# repair_logrotate_rsyslog.sh — idempotent fix for duplicate rsyslog logrotate entries (T-305).
# Replaces /etc/logrotate.d/rsyslog with the aggressive policy and removes rsyslog-aggressive.
#
# Usage:
#   ./repair_logrotate_rsyslog.sh              # apply on all CLUSTER_NODES
#   ./repair_logrotate_rsyslog.sh --dry-run    # validate only (logrotate -d)
#   ./repair_logrotate_rsyslog.sh --node NAME  # single node

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../../common.sh" ]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/../../common.sh"
else
    CLUSTER_NODES=("oci-k8s-master" "oci-k8s-node-1" "oci-k8s-node-2" "oci-k8s-node-3")
fi

DRY_RUN=0
SINGLE_NODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --node) SINGLE_NODE="${2:-}"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--node HOST]"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ -n "$SINGLE_NODE" ]; then
    NODES=("$SINGLE_NODE")
else
    NODES=("${CLUSTER_NODES[@]}")
fi

LOGROTATE_CONF='# T-202/T-305: aggressive syslog rotation (production-site cluster)
# Single source of truth — do not add rsyslog-aggressive (duplicates paths).
/var/log/syslog
/var/log/auth.log
/var/log/kern.log
/var/log/daemon.log {
    daily
    rotate 3
    compress
    delaycompress
    maxsize 200M
    missingok
    notifempty
    sharedscripts
    postrotate
        /usr/lib/rsyslog/rsyslog-rotate
    endscript
}
'

# Workers: SSH público costuma falhar no WSL; jump via master + hostname interno (Tailscale SSH).
MASTER_JUMP="${MASTER_NODE:-oci-k8s-master}"
ssh_target() {
    local node=$1
    case "$node" in
        oci-k8s-node-1) echo "${MASTER_JUMP}|k8s-node-1" ;;
        oci-k8s-node-2) echo "${MASTER_JUMP}|k8s-node-2" ;;
        oci-k8s-node-3) echo "${MASTER_JUMP}|k8s-node-3" ;;
        *) echo "$node|" ;;
    esac
}

run_on_node() {
    local node=$1
    local remote_cmd=$2
    local target jump_host inner
    target=$(ssh_target "$node")
    jump_host="${target%%|*}"
    inner="${target#*|}"
    if [ -n "$inner" ]; then
        ssh -T -o StrictHostKeyChecking=no -o ConnectTimeout=20 "$jump_host" \
            "ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new $inner $(printf '%q' "$remote_cmd")"
    else
        ssh -T -o StrictHostKeyChecking=no -o ConnectTimeout=20 "$jump_host" "$remote_cmd"
    fi
}

tee_on_node() {
    local node=$1
    local target jump_host inner
    target=$(ssh_target "$node")
    jump_host="${target%%|*}"
    inner="${target#*|}"
    if [ -n "$inner" ]; then
        ssh -T -o StrictHostKeyChecking=no -o ConnectTimeout=20 "$jump_host" \
            "ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new $inner 'sudo tee /etc/logrotate.d/rsyslog > /dev/null'"
    else
        ssh -T -o StrictHostKeyChecking=no -o ConnectTimeout=20 "$jump_host" \
            "sudo tee /etc/logrotate.d/rsyslog > /dev/null"
    fi
}

repair_node() {
    local node=$1
    echo "   [${node}]"
    if [ "$DRY_RUN" -eq 1 ]; then
        run_on_node "$node" "sudo logrotate -d /etc/logrotate.conf 2>&1" | tail -5
        return
    fi

    run_on_node "$node" \
        "sudo mkdir -p /var/backups/logrotate; \
         sudo cp -a /etc/logrotate.d/rsyslog /var/backups/logrotate/rsyslog.bak.\$(date +%Y%m%d%H%M%S) 2>/dev/null || true; \
         sudo rm -f /etc/logrotate.d/rsyslog.bak.* /etc/logrotate.d/rsyslog-aggressive"
    echo "$LOGROTATE_CONF" | tee_on_node "$node"
    if run_on_node "$node" "sudo logrotate -d /etc/logrotate.conf 2>&1 | grep -q 'error:'"; then
        echo '      ❌ logrotate still reports errors' >&2
        run_on_node "$node" "sudo logrotate -d /etc/logrotate.conf 2>&1 | grep error || true"
        return 1
    fi
    run_on_node "$node" "sudo systemctl reset-failed logrotate.service 2>/dev/null || true"
    echo '      ✅ logrotate config OK'
}

echo -e "\n📝 Repair logrotate rsyslog policy (T-305) — dry_run=${DRY_RUN}"
for node in "${NODES[@]}"; do
    repair_node "$node"
done
echo -e "✅ Done.\n"
