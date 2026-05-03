#!/bin/bash
set -euo pipefail

echo "🚀 Deploying Longhorn v1.11.1 (Optimized)..."

kubectl apply -f longhorn.yaml

echo "⏳ Waiting for Longhorn components..."
kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer --timeout=2m || true
kubectl -n longhorn-system rollout status deploy/longhorn-ui --timeout=2m || true

echo "Applying StorageClasses..."
kubectl apply -f storage-class-1.yaml
kubectl apply -f storage-class-2.yaml

echo "Applying custom Settings (non-default cluster overrides)..."
# Wait briefly for CRDs to be ready after fresh install
kubectl wait crd/settings.longhorn.io --for=condition=Established --timeout=60s 2>/dev/null || true
kubectl apply -f settings.yaml

echo "✅ Longhorn deployed."
