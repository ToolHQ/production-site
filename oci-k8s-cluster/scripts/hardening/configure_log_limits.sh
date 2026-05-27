#!/bin/bash
# scripts/hardening/configure_log_limits.sh
# Applies limits to Systemd Journal and Docker Logs to prevent disk exhaustion.
#
# OCI-optimised limits (1 vCPU / 6 GB RAM per node):
#   SystemMaxUse=200M      — cap total journal at 200 MB (prevents coroot-node-agent
#                            re-reading GB of archived journals after restarts → iowait)
#   SystemKeepFree=500M    — always keep 500 MB free on disk
#   SystemMaxFileSize=50M  — max size of a single journal file (faster rotation)
#   MaxRetentionSec=7day   — auto-expire journals older than 7 days
#   RuntimeMaxUse=50M      — volatile /run journals cap
#
# Root cause mitigated: T-293 (2026-05-24) — coroot-node-agent reading 1 GB of
# archived journals after 5 restarts caused 145 MB/s disk I/O → 76% iowait → CPU 100%.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source common for node list if available, else standard define
if [ -f "$SCRIPT_DIR/../../common.sh" ]; then
    source "$SCRIPT_DIR/../../common.sh"
else
    # Fallback
    CLUSTER_NODES=("oci-k8s-master" "oci-k8s-node-1" "oci-k8s-node-2" "oci-k8s-node-3")
fi

echo -e "\n🛡️  Applying Log Limits (OCI-optimised: 200M journal cap)..."

apply_node() {
    local node=$1
    echo -e "   [${node}] Applying configuration..."
    
    ssh -T -o StrictHostKeyChecking=no "$node" <<'EOF'
    set -e
    
    # 1. Systemd Journal Configuration
    # --------------------------------
    echo "      - Configuring journald (200M cap)..."
    # Ensure directory exists just in case
    sudo mkdir -p /etc/systemd
    
    # Backup (once)
    if [ ! -f /etc/systemd/journald.conf.bak ]; then
        sudo cp /etc/systemd/journald.conf /etc/systemd/journald.conf.bak
    fi
    
    # Apply OCI-optimised limits.
    # sed: replace existing (commented or not) lines; append if not present.
    apply_or_append() {
        local key="$1" val="$2" file="/etc/systemd/journald.conf"
        if sudo grep -qE "^#?${key}=" "$file"; then
            sudo sed -i "s|^#\?${key}=.*|${key}=${val}|" "$file"
        else
            echo "${key}=${val}" | sudo tee -a "$file" > /dev/null
        fi
    }
    apply_or_append SystemMaxUse      200M
    apply_or_append SystemKeepFree    500M
    apply_or_append SystemMaxFileSize  50M
    apply_or_append MaxRetentionSec   7day
    apply_or_append RuntimeMaxUse      50M
    
    # Reload
    echo "      - Restarting journald..."
    sudo systemctl restart systemd-journald
    
    # Immediately vacuum existing archived journals to the new limit
    echo "      - Vacuuming archived journals (--vacuum-size=200M)..."
    sudo journalctl --vacuum-size=200M 2>&1 | grep -E "Deleted|Freed|freed|No archive" || true
    AFTER=$(sudo journalctl --disk-usage 2>/dev/null | grep -oP '[0-9.]+ [A-Z]' | tail -1)
    echo "      - Journal disk usage after vacuum: ${AFTER:-unknown}"
    
    # 2. Docker Log Driver Configuration
    # --------------------------------
    if command -v docker >/dev/null 2>&1; then
        echo "      - Configuring Docker daemon..."
        sudo mkdir -p /etc/docker
        
        # Check if daemon.json exists
        if [ ! -f /etc/docker/daemon.json ]; then
            echo "{}" | sudo tee /etc/docker/daemon.json > /dev/null
        fi
        
        # Use simple temp file json manipulation with jq if available, else python or manual
        # Let's assume jq is likely missing or old, python3 is safer
        
        sudo python3 -c '
import json
import os

path = "/etc/docker/daemon.json"
try:
    with open(path, "r") as f:
        data = json.load(f)
except Exception:
    data = {}

# Set log options
data["log-driver"] = "json-file"
if "log-opts" not in data:
    data["log-opts"] = {}

data["log-opts"]["max-size"] = "100m"
data["log-opts"]["max-file"] = "3"

with open(path, "w") as f:
    json.dump(data, f, indent=4)
'
        # Restart Docker to apply
        echo "      - Restarting docker..."
        sudo systemctl restart docker
    else
        echo "      - Docker not found, skipping."
    fi
    
    echo "      ✅ Limits Applied."
EOF
}

for node in "${CLUSTER_NODES[@]}"; do
    apply_node "$node"
done
echo -e "✅ All nodes configured.\n"

# ---------------------------------------------------------------------------
# Phase 2: Aggressive logrotate for rsyslog (T-202 2026-05-03)
# Default Ubuntu logrotate keeps 7 rotations — syslog.1 can grow to 3G+.
# Override: daily rotation, max 3 kept, compress immediately, maxsize 200M.
# ---------------------------------------------------------------------------

echo -e "\n📝 Applying rsyslog logrotate policy (T-305: single file, no duplicates)..."
"$SCRIPT_DIR/repair_logrotate_rsyslog.sh"
