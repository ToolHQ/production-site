#!/usr/bin/env bash
# scripts/maintenance/fix_registry_hosts.sh
# Ensures registry.local points to 127.0.0.1 on all nodes

echo -e "${YELLOW}🔧 Verifying registry.local DNS on all nodes...${NC}"

# Source common for NODES if available, else detect
# Assuming executed from menu context where common vars are present or can be sourced
# But for robustness, we'll detect.

NODES=$(kubectl get nodes -o jsonpath='{.items[*].metadata.name}')

for node in $NODES; do
    echo -n "   • Splinting $node... "
    # Check if entry exists
    if ssh "$node" "grep -q 'registry.local' /etc/hosts"; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Fixing...${NC}"
        ssh "$node" "echo '127.0.0.1 registry.local' | sudo tee -a /etc/hosts >/dev/null"
        
        if [ $? -eq 0 ]; then
            echo -e "     ${GREEN}✅ Fixed${NC}"
        else
            echo -e "     ${RED}❌ Failed to apply${NC}"
        fi
    fi
done

echo -e "${GREEN}✨ Registry DNS check complete!${NC}"
