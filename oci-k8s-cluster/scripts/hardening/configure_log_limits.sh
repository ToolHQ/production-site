#!/bin/bash
# scripts/hardening/configure_log_limits.sh
# Applies limits to Systemd Journal and Docker Logs to prevent disk exhaustion.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source common for node list if available, else standard define
if [ -f "$SCRIPT_DIR/../../common.sh" ]; then
    source "$SCRIPT_DIR/../../common.sh"
else
    # Fallback
    CLUSTER_NODES=("oci-k8s-master" "oci-k8s-node-1" "oci-k8s-node-2" "oci-k8s-node-3")
fi

echo -e "\n🛡️  Thinking... Applying Log Limits (Closing the Faucets)..."

apply_node() {
    local node=$1
    echo -e "   [${node}] Applying configuration..."
    
    ssh -T -o StrictHostKeyChecking=no "$node" <<'EOF'
    set -e
    
    # 1. Systemd Journal Configuration
    # --------------------------------
    echo "      - Configuring journald..."
    # Ensure directory exists just in case
    sudo mkdir -p /etc/systemd
    
    # Backup
    if [ ! -f /etc/systemd/journald.conf.bak ]; then
        sudo cp /etc/systemd/journald.conf /etc/systemd/journald.conf.bak
    fi
    
    # Apply Limits (1G Max, Keep 2G Free always)
    # Using sed to replace or append if missing
    sudo sed -i 's/^#\?SystemMaxUse.*/SystemMaxUse=1G/' /etc/systemd/journald.conf
    sudo sed -i 's/^#\?SystemKeepFree.*/SystemKeepFree=2G/' /etc/systemd/journald.conf
    sudo sed -i 's/^#\?RuntimeMaxUse.*/RuntimeMaxUse=200M/' /etc/systemd/journald.conf
    
    # Reload
    echo "      - Restarting journald..."
    sudo systemctl restart systemd-journald
    
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
    apply_node "$node" &
done
wait
echo -e "✅ All nodes configured.\n"
