#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "=========================="
echo "🛠️  OS-Level DNS Doctor"
echo "=========================="

fix_os_network_stack() {
  local node="$1"

  log_node "$node" "🔍 Checking + fixing host DNS stack..."

  run_remote_stream "$node" "bash -euxo pipefail <<'EOF_OS'

echo '===== CHECKING /etc/resolv.conf ====='
cat /etc/resolv.conf || true

# Fix #1 resolv.conf uses 127.0.0.53 but service dead
if grep -q '127.0.0.53' /etc/resolv.conf; then
  echo '⚠️ resolv.conf uses 127.0.0.53 — checking systemd-resolved...'
  if ! systemctl is-active systemd-resolved >/dev/null 2>&1; then
    echo '🔧 systemd-resolved NOT running → rewriting resolv.conf'
    sudo rm -f /etc/resolv.conf
    echo 'nameserver 169.254.169.254' | sudo tee /etc/resolv.conf >/dev/null
  fi
fi

# Fix #2 resolv.conf broken
if ! grep -q 'nameserver' /etc/resolv.conf; then
  echo '⚠️ resolv.conf corrupted — rebuilding'
  echo 'nameserver 169.254.169.254' | sudo tee /etc/resolv.conf >/dev/null
fi

echo '===== CHECKING systemd-resolved ====='
if ! systemctl is-active systemd-resolved >/dev/null 2>&1; then
  echo '🔧 enabling + starting systemd-resolved'
  sudo systemctl enable systemd-resolved || true
  sudo systemctl start systemd-resolved || true
fi

echo '===== CHECKING network namespaces ====='
sudo ip netns list || true

# Clean up orphaned CNI namespaces (can accumulate from pod restarts/BuildKit)
echo '===== CLEANING orphaned CNI namespaces ====='
for ns in \$(sudo ip netns list | awk '{print \$1}'); do
  if [[ \$ns == cni-* ]]; then
    echo '🔧 Removing orphaned CNI namespace:' \$ns
    sudo ip netns delete \$ns || true
  elif [[ \$ns == *rootless* ]] || [[ \$ns == *slirp* ]]; then
    echo '🔧 Removing ghost namespace:' \$ns
    sudo ip netns delete \$ns || true
  fi
done

echo '===== CHECKING mountpoints for rootlesskit ====='
mount | grep -E 'rootless|slirp|copy-up' || true

for m in \$(mount | grep -E 'rootless|slirp|copy-up' | awk '{print \$3}'); do
  echo '🔧 Unmounting:' \$m
  sudo umount -f \$m || true
done

echo '===== Restarting host networking ====='
sudo systemctl restart systemd-networkd || true

echo '===== Restarting containerd + kubelet ====='
sudo systemctl restart containerd || true
sudo systemctl restart kubelet || true

echo '===== RECHECKING DNS ====='
if dig +time=3 +tries=1 kubernetes.default.svc.cluster.local @10.96.0.10 >/dev/null 2>&1; then
  echo 'OS_DNS_REMEDIATION=OK'
else
  echo 'OS_DNS_REMEDIATION=BROKEN'
fi

EOF_OS"
}

declare -a broken_os=()

for n in "${NODES[@]}"; do
  fix_os_network_stack "$n"

  run_remote_capture "$n" "grep OS_DNS_REMEDIATION /tmp/os_recheck 2>/dev/null || true"

  if grep -q "BROKEN" <<< "$RUN_REMOTE_CAPTURE_RESULT"; then
    broken_os+=("$n")
  fi
done

echo "=========================="
echo "✔️  Completed OS DNS Doctor"
echo "=========================="
