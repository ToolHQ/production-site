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

# Grafana desabilitado via values.yaml (grafana.enabled: false)
# Se deployment legado ainda existir no cluster, escalar para 0
if kubectl get deployment -n kubecost kubecost-grafana >/dev/null 2>&1; then
    kubectl scale deployment -n kubecost kubecost-grafana --replicas=0
    echo "  - kubecost-grafana desabilitado (replicas=0) — legado"
fi

echo "✅ Kubecost deployed."
