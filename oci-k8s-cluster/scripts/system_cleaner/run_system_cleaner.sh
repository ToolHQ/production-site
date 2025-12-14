#!/bin/bash
# run_system_cleaner.sh
# Orchestrates the execution of clean_node.sh on target nodes.
# Usage: ./run_system_cleaner.sh <node_name>

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common.sh"
source "$SCRIPT_DIR/../../scripts/volume_manager/vm_utils.sh"

NODE=$1

if [ -z "$NODE" ]; then
    echo "Usage: $0 <node_name>"
    exit 1
fi

PAYLOAD_SCRIPT="$SCRIPT_DIR/clean_node.sh"
REMOTE_PATH="/tmp/clean_node.sh"

echo "🚀 Deploying System Cleaner to $NODE..."

# 1. SCP the script
scp -o StrictHostKeyChecking=no -q "$PAYLOAD_SCRIPT" "$NODE:$REMOTE_PATH"

# 2. Make executable
ssh -o StrictHostKeyChecking=no "$NODE" "chmod +x $REMOTE_PATH"

# 3. Execute
ssh -o StrictHostKeyChecking=no -t "$NODE" "sudo $REMOTE_PATH"

# 4. Cleanup
ssh -o StrictHostKeyChecking=no "$NODE" "rm $REMOTE_PATH"

echo "✨ System Cleanup completed for $NODE"
