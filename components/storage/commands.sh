#!/usr/bin/env bash
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Managed by Antigravity (T-100)

echo "📦 Tuning Longhorn Resources..."

# 1. Apply LimitRange
kubectl apply -f "$dir/longhorn-limit-range.yaml"

# 2. Patch Manager (DaemonSet)
if kubectl get daemonset -n longhorn-system longhorn-manager >/dev/null 2>&1; then
    kubectl patch daemonset -n longhorn-system longhorn-manager --patch-file "$dir/longhorn-manager-patch.yaml"
    echo "  - Patched longhorn-manager"
fi

# 3. Patch UI (Deployment)
if kubectl get deployment -n longhorn-system longhorn-ui >/dev/null 2>&1; then
    kubectl patch deployment -n longhorn-system longhorn-ui --patch-file "$dir/longhorn-ui-patch.yaml"
    echo "  - Patched longhorn-ui"
fi

# 4. Patch Driver Deployer (Deployment)
if kubectl get deployment -n longhorn-system longhorn-driver-deployer >/dev/null 2>&1; then
    kubectl patch deployment -n longhorn-system longhorn-driver-deployer --patch-file "$dir/longhorn-driver-deployer-patch.yaml"
    echo "  - Patched longhorn-driver-deployer"
fi

echo "✅ Longhorn resources tuned."
