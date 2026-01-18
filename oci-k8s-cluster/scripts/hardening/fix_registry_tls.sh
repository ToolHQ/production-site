#!/bin/bash
source "$(dirname "$0")/../../common.sh"
source "$(dirname "$0")/../../lib/i18n.sh"

echo -e "${BLUE}🔧 Patching Containerd for Insecure Registry (registry.local:31444)...${NC}"

# Define the config block to append
CONFIG_BLOCK='
[plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.local:31444"]
  endpoint = ["http://registry.local:31444"]

[plugins."io.containerd.grpc.v1.cri".registry.configs."registry.local:31444".tls]
  insecure_skip_verify = true
'

for node in "${NODES[@]}"; do
    echo -e "\n${YELLOW}➡ Processing node: $node${NC}"
    
    # Check if already patched
    if ssh "$node" "grep -q 'registry.local:31444' /etc/containerd/config.toml"; then
         echo -e "${GREEN}   ✅ Already configured.${NC}"
    else
         echo -e "${CYAN}   📝 Appending configuration...${NC}"
         # Use sudo tee -a to append properly with permissions
         echo "$CONFIG_BLOCK" | ssh "$node" "sudo tee -a /etc/containerd/config.toml > /dev/null"
         
         echo -e "${CYAN}   🔄 Restarting containerd...${NC}"
         ssh "$node" "sudo systemctl restart containerd"
         echo -e "${GREEN}   ✅ Restarted.${NC}"
    fi
done

echo -e "\n${GREEN}✨ All nodes patched.${NC}"
