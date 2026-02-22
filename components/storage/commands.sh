#!/bin/bash
set -euo pipefail
# Managed by Antigravity (T-100)

echo "📦 Tuning Longhorn Resources..."

# 1. Apply LimitRange
kubectl apply -f longhorn-limit-range.yaml

# 2. Patch Manager (DaemonSet)
if kubectl get daemonset -n longhorn-system longhorn-manager >/dev/null 2>&1; then
    kubectl patch daemonset -n longhorn-system longhorn-manager --patch-file longhorn-manager-patch.yaml
    echo "  - Patched longhorn-manager"
fi

# 3. Patch UI (Deployment)
if kubectl get deployment -n longhorn-system longhorn-ui >/dev/null 2>&1; then
    kubectl patch deployment -n longhorn-system longhorn-ui --patch-file longhorn-ui-patch.yaml
    echo "  - Patched longhorn-ui"
fi

echo "✅ Longhorn resources tuned."
