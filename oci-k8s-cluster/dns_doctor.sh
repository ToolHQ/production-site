#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

echo "============================================================"
echo "🧪 DNS Doctor — Kubernetes DNS plane (CoreDNS + Cilium)"
echo "============================================================"

restart_dns_plane() {
  local node="$1"

  log_node "$node" "♻️ Restarting CoreDNS + Cilium..."

  run_remote_stream "$node" "bash -eu -o pipefail <<'EOF_RESTART'
kubectl -n kube-system rollout restart deploy/coredns || true
kubectl -n kube-system rollout restart ds/cilium || true

echo '⏳ Waiting for CoreDNS...'
kubectl -n kube-system rollout status deploy/coredns --timeout=5m || true

echo '⏳ Waiting for Cilium...'
kubectl -n kube-system rollout status ds/cilium --timeout=10m || true

echo '✅ DNS plane restarted'
EOF_RESTART"
}

probe_dns() {
  local node="$1"

  log_node "$node" "🔍 Probing DNS..."

  run_remote_capture "$node" "bash -eu -o pipefail <<'EOF_PROBE'
echo '📡 Probing DNS -> 10.96.0.10:53...'

# Install dig if needed
if ! command -v dig >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -qq || true
  sudo apt-get install -y -qq dnsutils || true
fi

if dig +time=3 +tries=1 @10.96.0.10 kubernetes.default.svc.cluster.local A >/dev/null 2>&1; then
  echo 'DNS_PROBE_RESULT=OK'
else
  echo 'DNS_PROBE_RESULT=BROKEN'
fi
EOF_PROBE"

  echo "$RUN_REMOTE_CAPTURE_RESULT"
}

fix_dns_node() {
  local node="$1"

  log_node "$node" "⚠️ DNS failed — applying remediation..."

  run_remote_capture "$node" "bash -eu -o pipefail <<'EOF_FIX'
echo '🔧 Restarting containerd + kubelet...'

sudo systemctl restart containerd || true
sudo systemctl restart kubelet || true

echo '⏳ Waiting 10s...'
sleep 10

echo '📡 Retesting DNS...'
if dig +time=3 +tries=1 @10.96.0.10 kubernetes.default.svc.cluster.local A >/dev/null 2>&1; then
  echo 'DNS_REMEDIATION_RESULT=OK'
else
  echo 'DNS_REMEDIATION_RESULT=BROKEN'
fi
EOF_FIX"

  echo "$RUN_REMOTE_CAPTURE_RESULT"
}

restart_dns_plane "$MASTER_NODE"

declare -a broken_nodes=()

for n in "${NODES[@]}"; do
  result=$(probe_dns "$n")

  if echo "$result" | grep -q "DNS_PROBE_RESULT=OK"; then
    log_node "$n" "🟢 DNS probe OK"
  else
    log_node "$n" "❌ DNS probe BROKEN"

    fix=$(fix_dns_node "$n")

    if echo "$fix" | grep -q "DNS_REMEDIATION_RESULT=OK"; then
      log_node "$n" "🟢 DNS fixed on this node"
    else
      log_node "$n" "🔴 DNS STILL BROKEN after remediation"
      broken_nodes+=("$n")
    fi
  fi
done

echo "============================================================"
echo "📊 DNS Doctor Summary"
echo "============================================================"
if (( ${#broken_nodes[@]} > 0 )); then
  echo "🔴 Some nodes still have DNS issues:"
  for b in "${broken_nodes[@]}"; do
    echo "   • $b"
  done
  echo "⚠️ Manual debugging required for the nodes above."
else
  echo "🟢 All nodes DNS are healthy!"
fi
