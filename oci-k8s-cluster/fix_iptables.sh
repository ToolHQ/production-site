#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

echo "============================================================"
echo "🔥 IPTables Fix — Ensuring Required K8s Ports are Open"
echo "============================================================"

# Required ports for Kubernetes cluster operation
REQUIRED_PORTS=(
  4240  # Cilium agent communication
  8472  # VXLAN encapsulation
  9500  # Longhorn backend API
  9502  # Longhorn admission webhook
  10250 # Kubelet API (already typically open)
)

fix_iptables_node() {
  local h="$1"
  
  log_node "$h" "🔍 Checking iptables rules..."
  
  run_remote_stream "$h" "bash -euxo pipefail <<'EOF_IPTABLES'
set -euo pipefail

echo '===== CURRENT INPUT CHAIN ====='
sudo iptables -L INPUT -n --line-numbers | head -20

echo '===== ADDING REQUIRED PORT RULES ====='
# Add rules for required ports (only if not already present)
for port in 4240 8472 9500 9502 10250; do
  if ! sudo iptables -C INPUT -p tcp --dport \$port -j ACCEPT 2>/dev/null; then
    echo \"🔧 Adding rule for port \$port\"
    sudo iptables -I INPUT -p tcp --dport \$port -j ACCEPT
  else
    echo \"✅ Port \$port already allowed\"
  fi
done

# Special handling for UDP 8472 (VXLAN)
if ! sudo iptables -C INPUT -p udp --dport 8472 -j ACCEPT 2>/dev/null; then
  echo '🔧 Adding rule for UDP 8472 (VXLAN)'
  sudo iptables -I INPUT -p udp --dport 8472 -j ACCEPT
else
  echo '✅ UDP 8472 (VXLAN) already allowed'
fi

echo '===== CHECKING FOR BLOCKING REJECT RULE ====='
if sudo iptables -L INPUT -n | grep -q 'REJECT.*icmp-host-prohibited'; then
  echo '⚠️  Found blocking REJECT rule'
  echo 'ℹ️  Note: Not removing automatically - may be intentional security policy'
  echo 'ℹ️  If cluster connectivity fails, manually run:'
  echo 'ℹ️    sudo iptables -D INPUT -j REJECT --reject-with icmp-host-prohibited'
else
  echo '✅ No blocking REJECT rule found'
fi

echo '===== FINAL INPUT CHAIN ====='
sudo iptables -L INPUT -n --line-numbers | head -20

echo 'IPTABLES_FIX=OK'

EOF_IPTABLES"
}

# Fix iptables on all nodes
for n in "${NODES[@]}"; do
  fix_iptables_node "$n"
done

echo
echo "============================================================"
echo "✅ IPTables fix completed on all nodes"
echo "   Note: Changes are NOT persistent across reboots"
echo "   Consider using iptables-persistent or netfilter-persistent"
echo "============================================================"
