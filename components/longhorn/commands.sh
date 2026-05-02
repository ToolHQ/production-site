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

echo "✅ Longhorn deployed."
