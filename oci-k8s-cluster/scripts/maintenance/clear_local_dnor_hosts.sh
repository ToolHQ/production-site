#!/usr/bin/env bash
# Remove local *.dnor.io overrides from Linux (/etc/hosts) and Windows hosts.
# Use when public DNS + OCI Security List (or Tailscale) should handle routing.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

marker="# Kubernetes Ingress Tunnels (dnor.io)"

clear_linux_hosts() {
    if [[ ! -f /etc/hosts ]]; then
        echo "No /etc/hosts found."
        return 0
    fi

    local before after
    before=$(grep -cE 'dnor\.io|Kubernetes Ingress Tunnels' /etc/hosts 2>/dev/null || true)
    before=${before:-0}

    sudo sed -i "/${marker}/d" /etc/hosts
    sudo sed -i '/Kubernetes Ingress Tunnels/d' /etc/hosts
    sudo sed -i '/\.dnor\.io/d' /etc/hosts

    after=$(grep -cE 'dnor\.io|Kubernetes Ingress Tunnels' /etc/hosts 2>/dev/null || true)
    after=${after:-0}

    echo -e "${GREEN}Linux /etc/hosts:${NC} removed $((before - after)) dnor.io override line(s)."
}

clear_windows_hosts() {
    if ! grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
        return 0
    fi

    echo -e "${BLUE}Clearing Windows hosts file via PowerShell...${NC}"
    powershell.exe -NoProfile -Command "
\$hostsPath = \"\$env:SystemRoot\System32\drivers\etc\hosts\"
\$backupPath = \"\$hostsPath.bak.clear-dnor-$(date +%s)\"
Copy-Item \$hostsPath \$backupPath -Force -ErrorAction SilentlyContinue
\$content = Get-Content \$hostsPath
\$newContent = @()
\$inBlock = \$false
foreach (\$line in \$content) {
    if (\$line -match 'Kubernetes.*Ingress.*Tunnels|dnor\.io') {
        if (\$line -match '#.*Kubernetes') { \$inBlock = \$true }
        continue
    }
    if (\$inBlock -and \$line.Trim() -eq '') { \$inBlock = \$false; continue }
    if (-not \$inBlock) { \$newContent += \$line }
}
Set-Content -Path \$hostsPath -Value \$newContent -Encoding ASCII
Write-Host \"Windows hosts cleaned (backup: \$backupPath)\"
" 2>/dev/null || echo -e "${YELLOW}Could not update Windows hosts (run PowerShell as Admin if needed).${NC}"
}

echo -e "${YELLOW}Removing local *.dnor.io /etc/hosts overrides...${NC}"
clear_linux_hosts
clear_windows_hosts

if getent ahosts reports.dnor.io 2>/dev/null | head -1 | grep -q '127.0.0.1'; then
    echo -e "${YELLOW}reports.dnor.io still resolves to 127.0.0.1 — check other DNS sources.${NC}"
else
    echo -e "${GREEN}reports.dnor.io now resolves via public DNS.${NC}"
    getent ahosts reports.dnor.io 2>/dev/null | head -1 || true
fi
