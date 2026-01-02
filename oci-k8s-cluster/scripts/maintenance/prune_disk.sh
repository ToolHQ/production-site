# scripts/maintenance/prune_disk.sh
# Frees up disk space on all nodes by removing unused images and old logs.

echo -e "${YELLOW}🧹 Pruning Disk Space on All Nodes...${NC}"

# Define function to run on each node
prune_node() {
    local node="$1"
    # Map k8s node name to SSH host alias if running locally
    local ssh_target="$node"
    if [[ "$node" == k8s-* ]]; then
        ssh_target="oci-$node"
    fi
    
    echo -e "\n🔹 Processing Node: ${CYAN}$node${NC} (via $ssh_target)"
    
    # 1. Prune Containerd Images
    echo -e "   • Pruning unused container images..."
    if ssh "$ssh_target" "sudo crictl rmi --prune" 2>/dev/null; then
         echo -e "     ${GREEN}Images pruned.${NC}"
    else
         echo -e "     ${RED}Image prune failed or timed out.${NC}"
    fi
    
    # 2. Vacuum Journal Logs
    echo -e "   • Vacuuming journal logs (keep 2days)..."
    ssh "$ssh_target" "sudo journalctl --vacuum-time=2d" 2>/dev/null
    
    # 3. Clean Apt Cache
    ssh "$ssh_target" "sudo apt-get clean" 2>/dev/null
    
    # 4. Show Result
    local usage
    usage=$(ssh "$ssh_target" "df -h / | tail -n 1 | awk '{print \$5}'")
    echo -e "   👉 Root Usage: ${GREEN}$usage${NC}"
}

# Run on Master (using k8s name which maps to oci-k8s-master)
prune_node "k8s-master"

# Get worker nodes
NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v "k8s-master")

for node in $NODES; do
    prune_node "$node"
done

echo -e "\n${GREEN}✨ Disk Pruning Complete!${NC}"
