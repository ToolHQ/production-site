#!/bin/bash
# scripts/security/scan_known_hosts.sh
# Scans cluster nodes and populates ~/.ssh/known_hosts
# Allows using StrictHostKeyChecking=accept-new safely

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../../common.sh" # Gets NODES

echo -e "${BLUE}🔑 Scan Known Hosts${NC}"
echo "   This script will fetch public keys from all cluster nodes"
echo "   and add them to your ~/.ssh/known_hosts file."
echo "   This prevents Man-in-the-Middle attacks."
echo ""

# Ensure known_hosts exists
touch ~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts

for node in "${NODES[@]}"; do
    echo -n "   Scanning $node... "
    
    # Check if we can resolve the node
    if getent hosts "$node" >/dev/null 2>&1; then
        # Remove old key to prevent duplicates/conflicts (optional, but cleaner for a fresh scan)
        ssh-keygen -R "$node" >/dev/null 2>&1
        
        # Scan and append
        keys=$(ssh-keyscan -H "$node" 2>/dev/null)
        if [ -n "$keys" ]; then
             echo "$keys" >> ~/.ssh/known_hosts
             echo -e "${GREEN}✓ Added${NC}"
        else
             echo -e "${RED}Failed (Network/Port issue?)${NC}"
        fi
    else
        echo -e "${RED}Skipped (Not resolvable)${NC}"
    fi
done

echo ""
echo -e "${GREEN}✅ Scan complete!${NC}"
echo "   You can now use 'StrictHostKeyChecking=accept-new' safely."
