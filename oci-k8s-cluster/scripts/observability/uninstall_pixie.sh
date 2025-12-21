#!/bin/bash
# scripts/observability/uninstall_pixie.sh
# Uninstalls Pixie

set -euo pipefail
UNINSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$UNINSTALL_DIR/../../common.sh"

echo "🗑️  Pixie Uninstall initiated..."

read -p "⚠️  Are you sure you want to remove Pixie? [y/N] " confirm
if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
   if command -v px &> /dev/null; then
       echo "📦 Running 'px deploy --delete'..."
       px deploy --delete || echo "⚠️  px deploy --delete failed."
   else
       echo "❌ px-cli not found. Cannot auto-uninstall."
   fi
   
   echo "🧹 Checking for remaining namespaces..."
   ssh oci-k8s-master "kubectl delete ns px pl --ignore-not-found" || true
   echo "✅ Pixie Uninstalled."
else
    echo "❌ Uninstall cancelled."
fi
