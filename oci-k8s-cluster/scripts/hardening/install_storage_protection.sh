#!/bin/bash
# scripts/hardening/install_storage_protection.sh
# Deploys the Storage Watchdog and Clean Node scripts to all cluster nodes.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Source common
if [ -f "$SCRIPT_DIR/../../common.sh" ]; then
    source "$SCRIPT_DIR/../../common.sh"
else
    CLUSTER_NODES=("oci-k8s-master" "oci-k8s-node-1" "oci-k8s-node-2" "oci-k8s-node-3")
fi

CLEANER_SRC="$SCRIPT_DIR/../../scripts/system_cleaner/clean_node.sh"
WATCHDOG_SRC="$SCRIPT_DIR/../../scripts/maintenance/storage_watchdog.sh"

echo -e "\n🛡️  Installing Storage Protection (Watchdog & Hardening)..."

install_node() {
    local node=$1
    echo -e "   [${node}] Installing..."
    
    # 1. Copy Files
    scp -O -o StrictHostKeyChecking=no "$CLEANER_SRC" "$node:/tmp/clean_node.sh" >/dev/null
    scp -O -o StrictHostKeyChecking=no "$WATCHDOG_SRC" "$node:/tmp/storage_watchdog.sh" >/dev/null
    
    # 2. Install & Cron
    ssh -T -o StrictHostKeyChecking=no "$node" <<'EOF'
    set -e
    
    # Move to bin
    sudo mv /tmp/clean_node.sh /usr/local/bin/clean_node.sh
    sudo mv /tmp/storage_watchdog.sh /usr/local/bin/storage_watchdog.sh
    
    sudo chmod +x /usr/local/bin/clean_node.sh
    sudo chmod +x /usr/local/bin/storage_watchdog.sh
    
    # Add to Cron (root) if not exists
    # Run every 5 minutes
    CRON_CMD="*/5 * * * * /usr/local/bin/storage_watchdog.sh"
    
    # Check if job exists
    if ! sudo crontab -l 2>/dev/null | grep -q "storage_watchdog.sh"; then
        (sudo crontab -l 2>/dev/null; echo "$CRON_CMD") | sudo crontab -
        echo "      - Cron job added."
    else
        echo "      - Cron job already exists."
    fi
    
    # Verify
    echo "      ✅ Installed."
EOF
}

for node in "${CLUSTER_NODES[@]}"; do
    install_node "$node" &
done
wait
echo -e "✅ Storage Protection Active on Cluster.\n"
