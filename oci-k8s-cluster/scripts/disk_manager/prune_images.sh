#!/bin/bash
# prune_images.sh
# Removes container images from a node via crictl.
# Usage: 
#   ./prune_images.sh <node_name> --prune             (Remove dangling images)
#   ./prune_images.sh <node_name> <image_id> ...      (Remove specific images)

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../volume_manager/vm_utils.sh"

NODE=$1
shift

if [ -z "$NODE" ]; then
    echo "Usage: $0 <node_name> [--prune | <image_id>...]"
    exit 1
fi

MODE=$1

# SSH Options
# Increased timeout for deletion operations
SSH_OPTS="-o ConnectTimeout=300 -o StrictHostKeyChecking=no"

if [ "$MODE" == "--prune" ]; then
    echo "🧹 Pruning dangling images on $NODE..."
    # ssh wrapper with long timeout
    ssh $SSH_OPTS "$NODE" "sudo crictl --timeout 300s rmi --prune"
    echo "✓ Prune completed."
    exit 0
fi

# Multi-image deletion
if [ -z "$MODE" ]; then
    echo "Error: No image IDs provided."
    exit 1
fi

echo "🗑️  Deleting ${#@} images on $NODE (Batched)..."

# Convert args to array
ALL_IMAGES=("$@")
TOTAL=${#ALL_IMAGES[@]}
BATCH_SIZE=5
CURRENT=0

# Iterate in batches
while [ $CURRENT -lt $TOTAL ]; do
    # Get batch slice
    BATCH=("${ALL_IMAGES[@]:$CURRENT:$BATCH_SIZE}")
    
    # Calculate progress
    END=$((CURRENT + ${#BATCH[@]}))
    echo "   ⏳ Processing batch $END/$TOTAL..."
    
    # Construct command
    # Using crictl with explicitly increased timeout (60s is usually enough per batch of 5)
    CMD="sudo crictl --timeout 60s rmi ${BATCH[*]}"
    
    # Run remote command
    if ssh $SSH_OPTS "$NODE" "$CMD"; then
        : # Success
    else
        echo "   ⚠️  Batch failed / Partial failure. Continuing..."
    fi
    
    CURRENT=$END
done

echo "✓ Deletion process completed."
exit 0
