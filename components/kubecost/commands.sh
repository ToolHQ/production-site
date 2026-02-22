#!/bin/bash
set -euo pipefail

echo "🚀 Deploying Kubecost with optimized resources..."

# Add repo if missing
helm repo add cost-analyzer https://kubecost.github.io/cost-analyzer/ >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || true

# Install/Upgrade
helm upgrade --install kubecost cost-analyzer/cost-analyzer \
    --namespace kubecost --create-namespace \
    --version 1.108.1 \
    --values values.yaml \
    --wait

echo "✅ Kubecost deployed."
