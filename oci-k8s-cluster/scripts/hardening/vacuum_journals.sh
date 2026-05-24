#!/bin/bash
# scripts/hardening/vacuum_journals.sh
# Vacuums old systemd journal archives on all (or a selected) cluster nodes.
#
# Root cause mitigated: T-293 (2026-05-24) — coroot-node-agent re-reads ALL
# archived journals after restarts. With 1 GB of archived journals this caused
# 145 MB/s disk I/O → 76% iowait → Prometheus reported CPU 100%.
#
# Usage:
#   ./vacuum_journals.sh                  # All nodes, --vacuum-time=7d
#   ./vacuum_journals.sh <node> [cutoff]  # e.g. oci-k8s-node-3 30d
#   Called by TUI: Node Hardening → "Vacuum Old Journals"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../../common.sh" ]; then
    source "$SCRIPT_DIR/../../common.sh"
else
    CLUSTER_NODES=("oci-k8s-master" "oci-k8s-node-1" "oci-k8s-node-2" "oci-k8s-node-3")
fi

# Default: keep last 7 days of journals
VACUUM_TIME="${2:-7d}"

vacuum_node() {
    local node="$1"
    echo -e "   [${node}] Vacuuming journals older than ${VACUUM_TIME}..."
    ssh -T -o StrictHostKeyChecking=no "$node" "
        BEFORE=\$(sudo journalctl --disk-usage 2>/dev/null | grep -oP '[0-9.]+ [A-Z].+' | head -1)
        sudo journalctl --vacuum-time=${VACUUM_TIME} 2>&1 | grep -E 'Deleted|Freed|freed|No archive' || true
        # Also enforce 200M size cap (belt and suspenders)
        sudo journalctl --vacuum-size=200M 2>&1 | grep -E 'Deleted|Freed|freed|No archive' || true
        AFTER=\$(sudo journalctl --disk-usage 2>/dev/null | grep -oP '[0-9.]+ [A-Z].+' | head -1)
        echo \"      Before: \${BEFORE:-unknown}  →  After: \${AFTER:-unknown}\"
    "
    if [ $? -eq 0 ]; then
        echo "      ✅ Done."
    else
        echo "      ⚠️  SSH failed or partial error on ${node}."
    fi
}

TARGET_NODE="${1:-}"

echo -e "\n🗑️  Systemd Journal Vacuum (cutoff: ${VACUUM_TIME})\n"

if [ -n "$TARGET_NODE" ]; then
    vacuum_node "$TARGET_NODE"
else
    for node in "${CLUSTER_NODES[@]}"; do
        vacuum_node "$node"
    done
fi

echo -e "\n✅ Journal vacuum complete.\n"
echo -e "ℹ️  To apply permanent retention limits, run: scripts/hardening/configure_log_limits.sh"
