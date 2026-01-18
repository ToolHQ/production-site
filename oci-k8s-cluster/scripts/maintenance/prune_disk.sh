#!/bin/bash
# scripts/maintenance/prune_disk.sh
# Wrapper to execute the robust 'clean_node.sh' on all cluster nodes.
# This replaces the old, flaky raw-SSH implementation.

# Rename to LOCAL_DIR to avoid overwriting parent SCRIPT_DIR when sourced
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common to get NODES and run_remote_stream
source "$LOCAL_DIR/../../common.sh"
# Source i18n for translations if needed
source "$LOCAL_DIR/../../lib/i18n.sh"

# Ensure GRAY is defined (fallback)
GRAY="${GRAY:-\033[1;30m}"

echo -e "${YELLOW}🧹 Triggering Cluster-Wide Cleanup...${NC}"
echo -e "${GRAY}   Strategy: Executing /usr/local/bin/clean_node.sh on all nodes${NC}"
echo ""

# Iterate over all detected nodes
for node in "${NODES[@]}"; do
    # Map k8s node name to SSH host alias if needed (handled by run_remote_stream logic usually, 
    # but here we use the NODES array which comes from SSH config in common.sh)
    
    echo -e "${BLUE}🔹 Connecting to Node: ${node}...${NC}"
    
    # We use run_remote_stream to get real-time output from the remote script
    # The script is already deployed to /usr/local/bin/clean_node.sh by install_storage_protection.sh
    if run_remote_stream "$node" "sudo /usr/local/bin/clean_node.sh"; then
        echo -e "${GREEN}   ✅ Node $node cleanup completed.${NC}"
    else
        echo -e "${RED}   ❌ Node $node cleanup failed or timed out.${NC}"
    fi
    echo "---------------------------------------------------"
done

echo -e "\n${GREEN}✨ All nodes processed.${NC}"
echo -e "${GRAY}   Check output above for detailed cleanup stats.${NC}"
