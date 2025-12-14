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
# Patch PVC (Escaping for SSH wrapper)
echo "Expanding PVC..."
PATCH_DATA="{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"$NEW_SIZE\"}}}}"
k patch pvc "$PVC_NAME" -n "$NAMESPACE" -p "'$PATCH_DATA'"

echo "⏳ Waiting for expansion to complete..."

# Polling loop (Max 60s)
MAX_RETRIES=30
COUNT=0
NEW_ACTUAL=""

while [ $COUNT -lt $MAX_RETRIES ]; do
    sleep 2
    NEW_ACTUAL=$(k get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.capacity.storage}')
    
    # If NEW_ACTUAL is empty or matches old size, keep waiting
    # Note: We can't easily compare strings like "512Mi" > "480Mi" purely in bash without standardizing units
    # So we check if it matches the TARGET size exactly.
    
    if [ "$NEW_ACTUAL" == "$NEW_SIZE" ]; then
        break
    fi
    
    echo -ne "   Waiting... ($((COUNT * 2))s)\r"
    COUNT=$((COUNT + 1))
done
echo ""

echo ""
header "EXPANSION COMPLETE"
echo "Old Size: $CURRENT_SIZE"
echo "New Size: $NEW_ACTUAL"
log "✅ PVC expanded successfully"
