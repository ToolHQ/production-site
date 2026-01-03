#!/bin/bash
set -euo pipefail

# Path to CredStore
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CREDSTORE_LIB="$SCRIPT_DIR/../../oci-k8s-cluster/lib/credstore.sh"

if [ ! -f "$CREDSTORE_LIB" ]; then
    echo "❌ Error: credstore.sh not found at $CREDSTORE_LIB" >&2
    exit 1
fi

source "$CREDSTORE_LIB"

echo "🔑 Retrieving Nexus credentials..." >&2
CRED_JSON=$(credstore_get_credential "nexus-admin")
USER=$(echo "$CRED_JSON" | jq -r '.username')
PASS=$(echo "$CRED_JSON" | jq -r '.password')

if [ -z "$PASS" ] || [ "$PASS" == "null" ]; then
    echo "❌ Error: Could not retrieve password for 'nexus-admin'" >&2
    exit 1
fi

TARGET_NS="${1:-}"

# Function to generate YAML for a single namespace
generate_yaml() {
    local ns="$1"
    kubectl create secret docker-registry "$SECRET_NAME" \
      --docker-server="$SERVER" \
      --docker-username="$USER" \
      --docker-password="$PASS" \
      --namespace="$ns" \
      --dry-run=client -o yaml
}

SECRET_NAME="regsecret"
SERVER="registry.local:31444"

if [ "$TARGET_NS" == "all" ] || [ -z "$TARGET_NS" ]; then
    echo "🌍 Fetching all namespaces from cluster..." >&2
    
    # Try local kubectl first, then fallback to SSH
    if command -v kubectl >/dev/null && kubectl get ns >/dev/null 2>&1; then
        NAMESPACES=$(kubectl get ns -o jsonpath='{.items[*].metadata.name}')
    else
        # Fallback to SSH. We assume 'oci-k8s-master' is the correct hostname as used in other scripts.
        HOST="oci-k8s-master"
        
        echo "   (using remote fetch via $HOST)" >&2
        NAMESPACES=$(ssh -o StrictHostKeyChecking=no "$HOST" "kubectl get ns -o jsonpath='{.items[*].metadata.name}'" 2>/dev/null)
    fi

    # Filter out namespaces if needed (optional), currently we do ALL
    FIRST=true
    for ns in $NAMESPACES; do
        if [ "$FIRST" == "true" ]; then
            FIRST=false
        else
            echo "---"
        fi
        echo "# Registry Secret for Namespace: $ns"
        generate_yaml "$ns"
    done
    
    echo "✅ Generated manifest for ALL namespaces." >&2
else
    # Single namespace
    echo "📦 Creating secret '$SECRET_NAME' in namespace '$TARGET_NS' for server '$SERVER'..." >&2
    generate_yaml "$TARGET_NS"
    echo "✅ Secret manifest generated successfully." >&2
fi
