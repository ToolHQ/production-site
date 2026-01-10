#!/bin/bash
set -euo pipefail

echo "🏰 Deploying Nexus..."

# 1. Apply Namespace
kubectl apply -f namespace.yaml

# 2. Safe PVC Application (Immutable Field Protection)
if kubectl get pvc -n nexus nexus-pvc >/dev/null 2>&1; then
    echo "💾 PVC nexus-pvc already exists. Skipping apply to avoid immutable field errors."
else
    echo "💾 Creating PVC nexus-pvc..."
    kubectl apply -f pvc.yaml
fi

# 3. Apply Resources
kubectl apply -f nexus.yaml

echo "✅ Nexus deployment applied."
