#!/bin/bash
set -euo pipefail

echo "🚀 Deploying Metrics Server (Optimized)..."

# Ensure kubelet-insecure-tls is set if using self-signed certs (common in simple setups)
# We patch the args locally if strictly needed, but let's assume the downloaded manifest + our resource patch is enough.
# Often metrics-server needs --kubelet-insecure-tls on DIY clusters.
# Let's add it via sed just in case, safe to be idempotent.

if ! grep -q "kubelet-insecure-tls" components.yaml; then
  sed -i '/args:/a \        - --kubelet-insecure-tls' components.yaml
fi

kubectl apply -f components.yaml
# T-100: Zero-Waste Patch
kubectl patch deployment metrics-server -n kube-system --patch-file patch-resources.yaml

echo "✅ Metrics Server deployed."
