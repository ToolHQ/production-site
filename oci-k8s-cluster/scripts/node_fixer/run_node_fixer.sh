#!/bin/bash
# run_node_fixer.sh
# Orchestrates the execution of fix_longhorn_reqs.sh on target nodes.
# Usage: ./run_node_fixer.sh <node_name>

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common.sh"
source "$SCRIPT_DIR/../../scripts/volume_manager/vm_utils.sh"

NODE=$1

if [ -z "$NODE" ]; then
    echo "Usage: $0 <node_name>"
    exit 1
fi

PAYLOAD_SCRIPT="$SCRIPT_DIR/fix_longhorn_reqs.sh"
REMOTE_PATH="/tmp/fix_longhorn_reqs.sh"

echo "🚀 Deploying Longhorn Fixer to $NODE..."

# 1. SCP the script
scp -o StrictHostKeyChecking=no -q "$PAYLOAD_SCRIPT" "$NODE:$REMOTE_PATH"

# 2. Make executable
ssh -o StrictHostKeyChecking=no "$NODE" "chmod +x $REMOTE_PATH"

# 3. Execute
ssh -o StrictHostKeyChecking=no -t "$NODE" "sudo $REMOTE_PATH"

# 4. Cleanup
ssh -o StrictHostKeyChecking=no "$NODE" "rm $REMOTE_PATH"

# 5. Restart Longhorn Manager (Required to detect changes)
echo "🔄 Restarting Longhorn Manager on $NODE..."
K8S_NODE_NAME=${NODE#oci-} # Convert oci-k8s-node-x -> k8s-node-x
k delete pod -n longhorn-system -l app=longhorn-manager --field-selector spec.nodeName=$K8S_NODE_NAME

echo "✨ Fix sequence completed for $NODE"
