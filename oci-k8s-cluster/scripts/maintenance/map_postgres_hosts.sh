#!/usr/bin/env bash
# scripts/maintenance/map_postgres_hosts.sh
# Maps 127.0.0.X loopback aliases to postgres domains in /etc/hosts via WSL/Sudo

set -euo pipefail

# ANSI Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Config
# 127.0.0.2 -> postgres.dnor.io (Primary)
# 127.0.0.3 -> postgres-ro.dnor.io (Replica)

echo -e "${YELLOW}🔧 Configuring DNS Aliases for Postgres Tunnels...${NC}"

# Function to add host entry if missing
ensure_host() {
    local ip="$1"
    local domain="$2"
    
    if grep -q "$domain" /etc/hosts; then
        echo -e "   • $domain already exists."
    else
        echo -e "   • ${YELLOW}Adding $domain -> $ip${NC}"
        echo "$ip $domain" | sudo tee -a /etc/hosts >/dev/null
    fi
}

echo "1. Checking Linux /etc/hosts..."
ensure_host "127.0.0.2" "postgres.dnor.io"
ensure_host "127.0.0.3" "postgres-ro.dnor.io"

echo -e "${GREEN}✅ Linux hosts configured.${NC}"

# Check for WSL and try to update Windows hosts (PowerShell)
if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}🪟 WSL Detected. Attempting to update Windows Hosts...${NC}"
    
    WIN_HOSTS_PATH="/mnt/c/Windows/System32/drivers/etc/hosts"
    
    if [ ! -w "$WIN_HOSTS_PATH" ]; then
        # Silent check - only show command if desired, or skip the warning for now to reduce noise
        :
    else
        # Try brute force append if mounted writable (unlikely in standard WSL)
         echo "127.0.0.2 postgres.dnor.io" >> "$WIN_HOSTS_PATH" 2>/dev/null || true
         echo "127.0.0.3 postgres-ro.dnor.io" >> "$WIN_HOSTS_PATH" 2>/dev/null || true
    fi
fi
