#!/usr/bin/env bash
set -e

# commands.sh for Longhorn
# Executed ON THE MASTER node by deploy_components.sh
# Assumes 'kubectl' is configured.

echo "📦 Deploying Longhorn (Distributed Block Storage)..."

# 1. Apply Patched YAML
if [ -f "longhorn.yaml" ]; then
    echo "    🚀 Applying local longhorn.yaml..."
    kubectl apply -f longhorn.yaml
else
    echo "    ❌ longhorn.yaml not found! Deployment failed."
    exit 1
fi

echo "    ⏳ Waiting for Longhorn system..."
kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer --timeout=5m || true
kubectl -n longhorn-system rollout status deploy/longhorn-ui --timeout=5m || true
kubectl -n longhorn-system rollout status ds/longhorn-manager --timeout=5m || true

# 2. Resilience Patches (Engine Timeouts)
# These are dynamic (DaemonSet names change based on engine version sometimes, or just safer to select by label)
echo "    🩹 Applying resilience patches..."
kubectl get ds -n longhorn-system -l longhorn.io/component=engine-image -o name | \
  xargs -I {} kubectl patch -n longhorn-system {} --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/timeoutSeconds", "value": 15}, {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/timeoutSeconds", "value": 15}]' || true

echo "✅ Longhorn deployment complete."
