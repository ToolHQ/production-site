#!/bin/bash
set -euo pipefail

# source common helpers if available
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ -f "$SCRIPT_DIR/../../common.sh" ]; then
    source "$SCRIPT_DIR/../../common.sh"
fi

echo "🧹 Starting Kubernetes Garbage Collection..."

# 1. Prune Evicted/Failed/Error Pods
echo "Step 1: Pruning Failed/Evicted Pods..."
# Get pods status
FAILED_PODS=$(kubectl get pods -A --field-selector=status.phase=Failed -o jsonpath='{.items[*].metadata.name}')
if [ -n "$FAILED_PODS" ]; then
    kubectl delete pods -A --field-selector=status.phase=Failed
    echo "✅ Deleted Failed pods."
else
    echo "✨ No Failed pods found."
fi

# 2. Prune Failed Jobs (Status: Failed)
echo "Step 2: Pruning Failed Jobs..."
# Logic: List jobs, check for .status.failed > 0
# We use a bit of jq magic or jsonpath to be precise
kubectl get jobs -A -o json | jq -r '.items[] | select(.status.failed > 0) | "\(.metadata.namespace) \(.metadata.name)"' | while read -r ns name; do
    if [ -n "$name" ]; then
        echo "🗑️  Deleting failed job: $ns/$name"
        kubectl delete job "$name" -n "$ns"
    fi
done

echo "✅ Garbage Collection Complete."
