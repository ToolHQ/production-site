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

NAMESPACE=${1:-postgres}
SECRET_NAME="regsecret"
SERVER="registry.local:31444"

echo "📦 Creating secret '$SECRET_NAME' in namespace '$NAMESPACE' for server '$SERVER'..." >&2

kubectl create secret docker-registry "$SECRET_NAME" \
  --docker-server="$SERVER" \
  --docker-username="$USER" \
  --docker-password="$PASS" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml

echo "✅ Secret manifest generated successfully." >&2
