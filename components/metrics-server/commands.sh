#!/bin/bash
set -euo pipefail

echo "🚀 Deploying Metrics Server (Optimized)..."

# Ensure kubelet-insecure-tls is set if using self-signed certs (common in simple setups)
# We patch the args locally if strictly needed, but let's assume the downloaded manifest + our resource patch is enough.
# Often metrics-server needs --kubelet-insecure-tls on DIY clusters.
# Let's add it via sed just in case, safe to be idempotent.

if ! grep -q "kubelet-insecure-tls" metrics-server.yaml; then
  sed -i '/args:/a \        - --kubelet-insecure-tls' metrics-server.yaml
fi

kubectl apply -f metrics-server.yaml

echo "✅ Metrics Server deployed."
