#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$dir/../.." && pwd)"
helm_cmd="$repo_root/tools/helm_compat.sh"

echo "🚀 Deploying Kubecost with optimized resources..."

# Add repo if missing
"$helm_cmd" repo add cost-analyzer https://kubecost.github.io/cost-analyzer/ >/dev/null 2>&1 || true
"$helm_cmd" repo update >/dev/null 2>&1 || true

# Install/Upgrade
"$helm_cmd" upgrade --install kubecost cost-analyzer/cost-analyzer \
    --namespace kubecost --create-namespace \
    --version 1.108.1 \
    --values "$dir/values.yaml" \
    --wait

if kubectl get deployment -n kubecost kubecost-grafana >/dev/null 2>&1; then
    kubectl patch deployment -n kubecost kubecost-grafana --patch-file "$dir/kubecost-grafana-patch.yaml"
    echo "  - Patched kubecost-grafana"
fi

echo "✅ Kubecost deployed."
