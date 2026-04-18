#!/bin/bash
set -euo pipefail

echo "🚀 Deploying Kubernetes Dashboard with optimized resources..."

# Add repo if missing
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true

# Install/Upgrade with local values
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard --create-namespace \
  --values values.yaml \
  --wait

for patch in dashboard-api-patch.yaml dashboard-web-patch.yaml dashboard-metrics-scraper-patch.yaml; do
  if [ -f "$patch" ]; then
    target="${patch%-patch.yaml}"
    kubectl -n kubernetes-dashboard patch deployment "$target" --patch-file "$patch"
    echo "  - Patched $target"
  fi
done

echo "✅ Dashboard deployed."

# Ensure admin token
kubectl -n kubernetes-dashboard create token admin-user --duration=24h 2>/dev/null | tee /tmp/dashboard_token.txt || true
echo "🔑 Token saved to /tmp/dashboard_token.txt on master."
