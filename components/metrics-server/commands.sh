#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Deploying Metrics Server (Optimized)..."

# Ensure kubelet-insecure-tls is set if using self-signed certs (common in simple setups)
# We patch the args locally if strictly needed, but let's assume the downloaded manifest + our resource patch is enough.
# Often metrics-server needs --kubelet-insecure-tls on DIY clusters.
# Let's add it via sed just in case, safe to be idempotent.

if ! grep -q "kubelet-insecure-tls" "$dir/components.yaml"; then
  sed -i '/args:/a \        - --kubelet-insecure-tls' "$dir/components.yaml"
fi

kubectl apply -f "$dir/components.yaml"
# T-100: Zero-Waste Patch
kubectl patch deployment metrics-server -n kube-system --patch-file "$dir/patch-resources.yaml"

echo "✅ Metrics Server deployed."
