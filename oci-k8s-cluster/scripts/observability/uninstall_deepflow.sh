#!/bin/bash
# scripts/observability/uninstall_deepflow.sh
# Uninstalls DeepFlow and cleans up PVCs

set -euo pipefail
UNINSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$UNINSTALL_DIR/../../common.sh"

echo "🗑️  DeepFlow Uninstall initiated..."

read -p "⚠️  Are you sure you want to completely remove DeepFlow and ALL DATA? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Uninstall cancelled."
    exit 0
fi

echo "📦 Uninstalling Helm Release..."
if ssh oci-k8s-master "helm list -n deepflow | grep -q deepflow"; then
  ssh oci-k8s-master "helm uninstall deepflow -n deepflow" || echo "⚠️ Helm uninstall failed or partially completed."
else
  echo "Helm release not found."
fi

echo "🧹 Cleaning up PVCs..."
# List PVCs and delete them
ssh oci-k8s-master "kubectl get pvc -n deepflow -o name | xargs -r kubectl delete -n deepflow" || true

echo "🧹 Cleaning up Namespace..."
ssh oci-k8s-master "kubectl delete ns deepflow --ignore-not-found" || true

echo "🧹 Pruning Longhorn Volumes (Optional)..."
echo "Note: Longhorn volumes will be marked for recurring deletion by Longhorn if PVCs are gone."

echo "✅ DeepFlow Uninstalled."
