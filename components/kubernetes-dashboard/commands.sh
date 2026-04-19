#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$dir/../.." && pwd)"
helm_cmd="$repo_root/tools/helm_compat.sh"

echo "🚀 Deploying Kubernetes Dashboard with optimized resources..."

# Add repo if missing
"$helm_cmd" repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ >/dev/null 2>&1 || true
"$helm_cmd" repo update >/dev/null 2>&1 || true

# Install/Upgrade with local values
"$helm_cmd" upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard --create-namespace \
  --values "$dir/values.yaml" \
  --wait

for patch in dashboard-api-patch.yaml dashboard-web-patch.yaml dashboard-metrics-scraper-patch.yaml; do
  if [ -f "$dir/$patch" ]; then
    target="${patch%-patch.yaml}"
    kubectl -n kubernetes-dashboard patch deployment "$target" --patch-file "$dir/$patch"
    echo "  - Patched $target"
  fi
done

echo "✅ Dashboard deployed."

# Ensure admin token
kubectl -n kubernetes-dashboard create token admin-user --duration=24h 2>/dev/null | tee /tmp/dashboard_token.txt || true
echo "🔑 Token saved to /tmp/dashboard_token.txt on master."
