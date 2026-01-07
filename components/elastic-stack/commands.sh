#!/bin/bash
set -e

# commands.sh for Elastic Stack Component
# Consolidates "Gatinho Mode" configs + Original Observability logic

echo "🐘 Starting Elastic Stack deployment (Consolidated)..."

# 0. Smart Build (Custom Images)
echo " [0] Running Smart Build..."
if [ -f "./build.sh" ]; then
    chmod +x ./build.sh
    ./build.sh
fi

# 1. ECK Operator (Critical Dependency)
echo " [1] Checking ECK Operator..."
if kubectl get ns elastic-system &> /dev/null; then
    if kubectl get pod -n elastic-system -l control-plane=elastic-operator | grep Running &> /dev/null; then
        echo "    ✅ ECK Operator is running."
    else
        echo "    🔄 Updating ECK Operator..."
        kubectl apply -f https://download.elastic.co/downloads/eck/2.10.0/crds.yaml || true
        kubectl apply -f https://download.elastic.co/downloads/eck/2.10.0/operator.yaml
    fi
else
    echo "    📥 Installing ECK Operator (v2.10.0)..."
    kubectl create -f https://download.elastic.co/downloads/eck/2.10.0/crds.yaml
    kubectl apply -f https://download.elastic.co/downloads/eck/2.10.0/operator.yaml
fi

# 1.5 Create Registry Secret (Required for Custom Images on Worker Nodes)
echo " [1.5] Configuring Registry Access..."
if [[ -n "$NEXUS_PASS" ]]; then
    # Use environment variables passed from deploy_components.sh
    # DOCKER_REGISTRY_HOST and PORT are usually set there too
    : "${DOCKER_REGISTRY_HOST:=127.0.0.1}"
    : "${PORT:=31444}"
    
    echo "    🔐 Creating 'regcred' secret in elastic-system..."
    kubectl create secret docker-registry regcred \
      --docker-server="${DOCKER_REGISTRY_HOST}:${PORT}" \
      --docker-username=admin \
      --docker-password="$NEXUS_PASS" \
      -n elastic-system \
      --dry-run=client -o yaml | kubectl apply -f -
else
    echo "    ⚠️  NEXUS_PASS not set. Attempting to clone 'regcred' from default namespace..."
    # Fallback: Copy from default if it exists
    kubectl get secret regcred -n default -o yaml 2>/dev/null | \
    sed 's/namespace: default/namespace: elastic-system/' | \
    kubectl apply -f - || echo "    ❌ Failed to create registry secret. Image pulls may fail."
fi

# 2. Apply Manifests
echo " [2] Applying Elastic Stack Configuration..."

# Apply Elasticsearch (Tuned: 2Gi limit)
echo "    🚀 Applying Elasticsearch..."
# Function to robustly apply manifests
apply_robust() {
    local file="$1"
    local name="$2" # e.g. elasticsearch/oci-logs
    
    echo "    🚀 Applying $name from $file..."
    if ! kubectl apply -f "$file" --server-side --force-conflicts; then
        echo "    ⚠️  Apply failed (Conflict). Forcing recreation of $name..."
        kubectl delete "$name" -n elastic-system --ignore-not-found --wait=true --timeout=60s
        sleep 5
        kubectl apply -f "$file" --server-side --force-conflicts
    fi
}

apply_robust "elasticsearch.yaml" "elasticsearch/oci-logs"

# Apply Kibana
kubectl delete kibana oci-logs -n elastic-system --ignore-not-found 2>/dev/null || true
apply_robust "kibana.yaml" "kibana/oci-logs"

# Apply Logstash
echo "    🚀 Applying Logstash..."

# 2.1 Create Logstash Patterns ConfigMap (Required for patterns-vol)
echo "      - Ensuring 'logstash-patterns' ConfigMap exists..."
kubectl create configmap logstash-patterns -n elastic-system \
  --from-literal=custom.patterns='TEST_PATTERN %{WORD}' \
  --dry-run=client -o yaml | kubectl apply -f -

# 2.2 Create Logstash Pipeline Secret (If missing)
# 2.2 Create Logstash Pipeline Secret (If missing)
echo "      - Ensuring 'logstash-pipeline' secret exists..."
# Use config.string in pipelines.yml to inline the pipeline definition
# This satisfies the 'missing key pipelines.yml' error from ECK Operator
cat <<EOF > /tmp/pipelines.yml
- pipeline.id: main
  config.string: |
    input {
      beats {
        port => 5044
      }
    }
    output {
      elasticsearch {
        hosts => ["https://oci-logs-es-http:9200"]
        user => "\${LOGSTASH_USER}"
        password => "\${LOGSTASH_PASSWORD}"
        ssl => true
        cacert => "/mnt/elastic-internal/elasticsearch-association/oci-logs/es-http/ca.crt"
        index => "filebeat-%%{[agent][version]}-%%{+YYYY.MM.dd}"
      }
    }
EOF

kubectl create secret generic logstash-pipeline -n elastic-system \
  --from-file=pipelines.yml=/tmp/pipelines.yml \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl delete logstash oci-logstash -n elastic-system --ignore-not-found 2>/dev/null || true
apply_robust "logstash.yaml" "logstash/oci-logstash"

# Apply Filebeat
kubectl delete beat oci-filebeat -n elastic-system --ignore-not-found 2>/dev/null || true
apply_robust "filebeat.yaml" "beat/oci-filebeat"

# Apply Ingress (Renamed from ingress.yaml)
echo "    🚀 Applying Kibana/ES Ingress..."
kubectl apply -f kibana-ingress.yaml

# 3. Wait for Rollout (Elasticsearch first)
echo " [3] Verifying Rollout Status..."
echo "    ⏳ Waiting for Elasticsearch (oci-logs-es-default)..."
# ECK creates a StatefulSet named {elasticsearch_name}-es-{nodeset_name}
if kubectl -n elastic-system rollout status statefulset/oci-logs-es-default --timeout=600s; then
    echo "    ✅ Elasticsearch is Ready."
else
    echo "    ⚠️  Elasticsearch timed out. Checking Operator logs..."
    kubectl -n elastic-system logs -l control-plane=elastic-operator --tail=20 || true
    echo "    🔍 Checking ES Pod logs..."
    kubectl -n elastic-system logs -l elasticsearch.k8s.elastic.co/cluster-name=oci-logs --tail=20 || true
fi

echo "    ⏳ Waiting for Logstash (oci-logstash)..."
# ECK creates a StatefulSet named {logstash_name}-ls
# Wait for STS to appear first (Operator might stagger creation)
echo "      - Waiting for StatefulSet 'oci-logstash-ls' to be created (Max 300s)..."
timeout=300
start_time=$(date +%s)
while ! kubectl get statefulset oci-logstash-ls -n elastic-system >/dev/null 2>&1; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    if [ $elapsed -ge $timeout ]; then
        echo "      ❌ Timed out waiting for StatefulSet creation."
        break
    fi
    # UX Improvement: Print a dot every 5 seconds, or progress every 30s
    if (( elapsed % 15 == 0 )); then
       echo -n "      Running($elapsed s)..."
    fi
    sleep 5
done
echo "" # Newline after loop

if kubectl -n elastic-system rollout status statefulset/oci-logstash-ls --timeout=300s; then
    echo "    ✅ Logstash is Ready."
else
    echo "    ⚠️  Logstash timed out."
    kubectl -n elastic-system describe statefulset oci-logstash-ls || echo "StatefulSet not found"
    kubectl -n elastic-system logs -l control-plane=elastic-operator --tail=20 || true
fi

# 4. Configure Kibana
echo " [4] Configuring Kibana..."
if [ -f "./configure_kibana.sh" ]; then
    chmod +x ./configure_kibana.sh
    ./configure_kibana.sh
else
    echo "    ⚠️  Configuration script not found."
fi

echo "📊 Elastic Stack Deployment Complete."
echo "   Kibana: https://kibana.dnor.io"
echo "   ES: https://es.dnor.io"

# Debug Info
echo ""
echo "🔍 Pod Status in elastic-system:"
kubectl get pods -n elastic-system -o wide
