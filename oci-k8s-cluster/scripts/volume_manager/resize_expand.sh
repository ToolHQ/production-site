#!/bin/bash
# PVC expansion (native Kubernetes feature)
# Part of T-017: TUI Volume Manager
# Refactored: Uses vm_utils.sh

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm_utils.sh"

usage() {
    echo "Usage: $0 <namespace> <pvc-name> <new-size>"
    echo "Example: $0 elastic-system elasticsearch-data-oci-logs-es-default-0 10Gi"
    exit 1
}

[ $# -ne 3 ] && usage

NAMESPACE=$1
PVC_NAME=$2
NEW_SIZE=$3

header "PVC EXPANSION"
echo "Namespace: $NAMESPACE"
echo "PVC: $PVC_NAME"
echo "New Size: $NEW_SIZE"
echo ""

# Get current size
CURRENT_SIZE=$(k get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.capacity.storage}')
echo "Current Size: $CURRENT_SIZE"

# Patch PVC
echo "Expanding PVC..."
k patch pvc "$PVC_NAME" -n "$NAMESPACE" -p "{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"$NEW_SIZE\"}}}}"

echo "⏳ Waiting for expansion to complete..."
sleep 5

# Check new size
NEW_ACTUAL=$(k get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.capacity.storage}')

echo ""
header "EXPANSION COMPLETE"
echo "Old Size: $CURRENT_SIZE"
echo "New Size: $NEW_ACTUAL"
log "✅ PVC expanded successfully"
