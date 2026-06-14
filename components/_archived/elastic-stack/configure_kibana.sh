#!/usr/bin/env bash
set -e

# configure_kibana.sh
# Automates the creation of Data Views in Kibana using a reliable in-pod script execution strategy.

NAMESPACE="elastic-system"
KIBANA_SVC="oci-logs-kb-http"
KIBANA_PORT=5601

echo "🔍 [Kibana Setup] Starting configuration..."

# 1. Wait for Kibana to be ready
echo "⏳ [Kibana Setup] Waiting for Kibana service..."
kubectl wait --for=condition=ready pod -l common.k8s.elastic.co/type=kibana -n "$NAMESPACE" --timeout=300s --insecure-skip-tls-verify > /dev/null 2>&1 || echo "⚠️  Kibana pod not ready yet, proceeding with caution..."

# 2. Retrieve Credentials (Locally)
echo "🔐 [Kibana Setup] Retrieving credentials..."
ES_USER="elastic"
ES_PASSWORD=$(kubectl get secret oci-logs-es-elastic-user -n "$NAMESPACE" -o go-template='{{.data.elastic | base64decode}}' --insecure-skip-tls-verify)

if [[ -z "$ES_PASSWORD" ]]; then
    echo "❌ [Kibana Setup] Failed to retrieve 'elastic' password. Exiting."
    exit 1
fi

# 3. Find Kibana Pod
KIBANA_POD=$(kubectl get pod -n "$NAMESPACE" -l common.k8s.elastic.co/type=kibana -o jsonpath='{.items[0].metadata.name}' --insecure-skip-tls-verify)
echo "🚀 [Kibana Setup] Target Pod: ${KIBANA_POD}"

# 4. Generate the payload script to run INSIDE the pod
# We use variable assignment via cat to avoid 'read' exit code issues with set -e
IN_POD_SCRIPT=$(cat <<EOF
#!/bin/bash
set -e

ES_USER="${ES_USER}"
ES_PASSWORD="${ES_PASSWORD}"
KIBANA_URL="https://localhost:5601"

echo "🔎 Waiting for Kibana API to accept connections..."
until curl -s -k -u "\$ES_USER:\$ES_PASSWORD" "\$KIBANA_URL/api/status" > /dev/null; do
    echo "   ... waiting for Kibana API ..."
    sleep 3
done

echo "🔎 Fetching all Data Views (Saved Objects)..."
# Use Saved Objects API to find everything, use sed to newline-delimit objects for grep
ALL_OBJECTS=\$(curl -s -k -u "\$ES_USER:\$ES_PASSWORD" "\$KIBANA_URL/api/saved_objects/_find?type=index-pattern&per_page=100" | sed 's/{"type":/\n{"type":/g')

# Function to delete a view by ID using Saved Objects API
delete_object() {
  local id=\$1
  echo "🗑️  Deleting Saved Object ID: \$id"
  # Note: Use saved_objects API for deletion to be sure
  curl -s -k -u "\$ES_USER:\$ES_PASSWORD" -X DELETE "\$KIBANA_URL/api/saved_objects/index-pattern/\$id" -H 'kbn-xsrf: true' > /dev/null
}

echo "\$ALL_OBJECTS" | while read -r line; do
  # Check for "Logs (Default)"
  if echo "\$line" | grep -q '"name":"Logs (Default)"'; then
      ID=\$(echo "\$line" | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)
      if [[ -n "\$ID" ]]; then
        echo "🔄 Found broken/legacy 'Logs (Default)' (ID: \$ID). Deleting..."
        delete_object "\$ID"
      fi
  fi

  # Check for "Logs (System)"
  if echo "\$line" | grep -q '"name":"Logs (System)"'; then
      ID=\$(echo "\$line" | grep -o '"id":"[^"]*"' | head -n 1 | cut -d'"' -f4)
      if [[ -n "\$ID" ]]; then
        echo "🧹 Cleaning up 'Logs (System)' (ID: \$ID)..."
        delete_object "\$ID"
      fi
  fi
done

# 3. Create fresh 'Logs (Default)' with @timestamp
echo "➕ Creating corrected Data View 'Logs (Default)'..."
curl -s -k -u "\$ES_USER:\$ES_PASSWORD" \
  -X POST "\$KIBANA_URL/api/data_views/data_view" \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '{
    "data_view": {
       "title": "logs-*",
       "name": "Logs (Default)",
       "timeFieldName": "@timestamp"
    }
  }'
echo ""
echo "✅ Configuration attempt complete."
EOF
)

# 5. Inject and Run the script
echo "$IN_POD_SCRIPT" | kubectl exec -i -n "$NAMESPACE" "$KIBANA_POD" --insecure-skip-tls-verify -- bash -c "cat > /tmp/setup_kibana_internal.sh && chmod +x /tmp/setup_kibana_internal.sh"
kubectl exec -n "$NAMESPACE" "$KIBANA_POD" --insecure-skip-tls-verify -- /tmp/setup_kibana_internal.sh

echo "✅ [Kibana Setup] Done."
