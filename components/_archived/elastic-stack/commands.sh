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
        kubectl apply -f operator.yaml
    fi
else
    echo "    📥 Installing ECK Operator (v2.10.0)..."
    kubectl create -f https://download.elastic.co/downloads/eck/2.10.0/crds.yaml
    kubectl apply -f operator.yaml
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

# 2.1 Create Logstash Config Secret (With Tunings)
echo "      - Ensuring 'logstash-config' secret exists..."
# We move Env Vars to logstash.yml to avoid ReadOnly FS errors in init containers
cat <<EOF > /tmp/logstash.yml
pipeline.workers: 1
pipeline.batch.size: 50
pipeline.batch.delay: 50
EOF

kubectl create secret generic logstash-config -n elastic-system \
  --from-file=logstash.yml=/tmp/logstash.yml \
  --dry-run=client -o yaml | kubectl apply -f -

# 2.1.5 Create Logstash Patterns ConfigMap (Required for patterns-vol)
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
        hosts => ["\${OCI_LOGS_ES_HOSTS}"]
        user => "\${LOGSTASH_USER}"
        password => "\${LOGSTASH_PASSWORD}"
        ssl => true
        cacert => "\${OCI_LOGS_ES_SSL_CERTIFICATE_AUTHORITY}"
        index => "filebeat-%{[agent][version]}-%{+YYYY.MM.dd}"
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

# Function: Smart Wait with Active Monitoring (Fail Fast & Success Fast)
smart_wait() {
    local namespace=$1
    local selector=$2
    local resource_name=$3
    local timeout=${4:-300}
    local success_pattern=${5:-""}

    echo "    ⏳ Monitoring $resource_name (Max ${timeout}s)..."
    local start_time=$(date +%s)
    local pods_found=false

    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            echo "      ❌ Timeout waiting for $resource_name."
            return 1
        fi

        # Get Pods JSON
        local pod_json=$(kubectl get pods -n "$namespace" -l "$selector" -o json 2>/dev/null)
        local pod_count=$(echo "$pod_json" | jq '.items | length')

        if [[ "$pod_count" == "0" ]]; then
            if [[ "$pods_found" == "true" ]]; then
                 echo "      ⚠️  Pods for $resource_name disappeared..."
                # Still waiting for operator to create pods
                 if (( elapsed % 10 == 0 )); then
                    echo "      - Waiting for pods to appear (Selector: $selector)..."
                 fi
            else
                 if (( elapsed % 10 == 0 )); then
                    echo "      - Waiting for pods to appear (Selector: $selector)..."
                 fi
            fi
            sleep 2
            continue
        fi
        
        pods_found=true

        # 1. Fail Fast: Check for CrashLoop/ImagePull
        local crash_pod=$(echo "$pod_json" | jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason == "CrashLoopBackOff") | .metadata.name' | head -n 1)
        if [[ -n "$crash_pod" ]]; then
            echo "      ❌ Detected CrashLoopBackOff in $crash_pod!"
            echo "      🔍 Recent Logs:"
            kubectl logs -n "$namespace" "$crash_pod" --tail=20 --all-containers
            return 1
        fi

        local image_err_pod=$(echo "$pod_json" | jq -r '.items[] | select(.status.containerStatuses[]?.state.waiting.reason == "ImagePullBackOff" or .status.containerStatuses[]?.state.waiting.reason == "ErrImagePull") | .metadata.name' | head -n 1)
        if [[ -n "$image_err_pod" ]]; then
            echo "      ❌ Detected Image Error in $image_err_pod!"
            echo "      🔍 Events:"
            kubectl describe pod -n "$namespace" "$image_err_pod" | grep -A 10 Events
            return 1
        fi
        
        # 2. Success Fast: Check Logs for Pattern (if provided)
        if [[ -n "$success_pattern" ]]; then
             # Check logs of all pods matching selector
             # We use 'grep -q' which exits 0 if matched
             if kubectl logs -n "$namespace" -l "$selector" --tail=50 --prefix=false 2>/dev/null | grep -Eq "$success_pattern"; then
                 echo "      ✅ Success Pattern Found: '$success_pattern'"
                 return 0
             fi
        fi

        # 3. Success Normal: Check Ready Conditions
        local ready_count=$(echo "$pod_json" | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')
        
        if [[ "$ready_count" -ge 1 ]] && [[ "$ready_count" -eq "$pod_count" ]]; then
             echo "      ✅ $resource_name is Ready ($ready_count/$pod_count pods)."
             return 0
        fi

        # Progress feedback with Log Snippet (User Feedback)
        if (( elapsed % 5 == 0 )); then
            local sample_pod=$(echo "$pod_json" | jq -r '.items[0].metadata.name')
            local sample_status=$(echo "$pod_json" | jq -r '.items[0].status.phase')
            
            # Get last log line for context
            local last_log=$(kubectl logs -n "$namespace" "$sample_pod" --tail=1 2>/dev/null | tr -d '\n\r' | cut -c 1-80)
            if [[ -z "$last_log" ]]; then last_log="(no logs yet)"; fi
            
            echo "      ▶ ${resource_name}: ${sample_status} (${elapsed}s) - \"${last_log}...\""
        fi
        
        sleep 3
    done
}

# 3. Wait for Rollout (Elasticsearch first)
echo " [3] Verifying Rollout Status..."

# Wait for Elasticsearch (Success on GREEN/YELLOW health)
smart_wait "elastic-system" "elasticsearch.k8s.elastic.co/cluster-name=oci-logs" "Elasticsearch" 600 "Cluster health status changed from .* to \[(GREEN|YELLOW)\]" || exit 1

# Wait for Logstash (Success on Pipeline started)
smart_wait "elastic-system" "logstash.k8s.elastic.co/name=oci-logstash" "Logstash" 300 "Successfully started Logstash API endpoint" || exit 1

# Wait for Kibana (Success on Status is Green or Ready)
smart_wait "elastic-system" "common.k8s.elastic.co/type=kibana" "Kibana" 300 "Kibana is now available" || exit 1

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
