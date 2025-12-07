#!/usr/bin/env bash
set -e

# configure_kibana.sh
# Automates the creation of Data Views in Kibana

NAMESPACE="elastic-system"
KIBANA_SVC="oci-logs-kb-http"
KIBANA_PORT=5601

echo "🔍 [Kibana Setup] Starting configuration..."

# 1. Wait for Kibana to be ready
echo "⏳ [Kibana Setup] Waiting for Kibana service..."
kubectl wait --for=condition=ready pod -l common.k8s.elastic.co/type=kibana -n "$NAMESPACE" --timeout=300s --insecure-skip-tls-verify > /dev/null 2>&1 || echo "⚠️  Kibana pod not ready yet, proceeding with caution..."

# 2. Retrieve Credentials
echo "🔐 [Kibana Setup] Retrieving credentials..."
ES_USER="elastic"
ES_PASSWORD=$(kubectl get secret oci-logs-es-elastic-user -n "$NAMESPACE" -o go-template='{{.data.elastic | base64decode}}' --insecure-skip-tls-verify)

if [[ -z "$ES_PASSWORD" ]]; then
    echo "❌ [Kibana Setup] Failed to retrieve 'elastic' password. Exiting."
    exit 1
fi

# 3. Create Data View (Index Pattern)
# We use a temporary pod to ensure we have network access to the ClusterIP service if running outside the cluster network.
# OR, if running on master node (which usually has access to ClusterIP via kube-proxy or CNI), we can try curl directly.
# Given this runs on master via deploy_components, we'll try direct curl to the ClusterIP first.

KIBANA_URL="https://${KIBANA_SVC}.${NAMESPACE}.svc:${KIBANA_PORT}"
# Note: internal service uses self-signed certs managed by ECK

DATA_VIEW_PAYLOAD='{
  "data_view": {
     "title": "logs-*",
     "name": "Logs (Default)",
     "timeFieldName": "app@timestamp"
  }
}'

echo "POSTing to ${KIBANA_URL}/api/data_views/data_view..."

# Using ephemeral pod for reliable internal network access
# kubectl run --rm -i --restart=Never kibana-config-job --image=curlimages/curl -- \
#   curl -s -k -u "${ES_USER}:${ES_PASSWORD}" \
#   -X POST "${KIBANA_URL}/api/data_views/data_view" \
#   -H "kbn-xsrf: true" \
#   -H "Content-Type: application/json" \
#   -d "$DATA_VIEW_PAYLOAD"

# For speed/simplicity on master node, we can use kubectl exec into the kibana pod itself to run curl (localhost)
KIBANA_POD=$(kubectl get pod -n "$NAMESPACE" -l common.k8s.elastic.co/type=kibana -o jsonpath='{.items[0].metadata.name}' --insecure-skip-tls-verify)

echo "🚀 [Kibana Setup] Executing configuration inside pod ${KIBANA_POD}..."

kubectl exec -n "$NAMESPACE" "$KIBANA_POD" --insecure-skip-tls-verify -- bash -c "
curl -s -k -u '${ES_USER}:${ES_PASSWORD}' \
  -X POST 'https://localhost:5601/api/data_views/data_view' \
  -H 'kbn-xsrf: true' \
  -H 'Content-Type: application/json' \
  -d '${DATA_VIEW_PAYLOAD}'
"

echo ""
echo "✅ [Kibana Setup] Request sent. (If 409 Conflict, it means it already exists)."
