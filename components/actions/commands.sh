#!/bin/bash
set -euo pipefail
# Zero-Waste T-100: App Limits

echo "📦 Applying App LimitRanges..."
NAMESPACES=("default" "nexus" "postgres")

for ns in "${NAMESPACES[@]}"; do
    if kubectl get ns "$ns" >/dev/null 2>&1; then
        echo "  - Applying to $ns..."
        kubectl apply -f app-limit-range.yaml -n "$ns"
    else
        echo "  - Skipping $ns (not found)"
    fi
done

echo "✅ App LimitRanges applied."
