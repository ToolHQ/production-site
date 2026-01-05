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

# 2. Apply Manifests
echo " [2] Applying Elastic Stack Configuration..."

# Apply Elasticsearch (Tuned: 2Gi limit)
echo "    🚀 Applying Elasticsearch..."
kubectl apply -f elasticsearch.yaml

# Apply Logstash (Tuned: 1.5Gi limit)
echo "    🚀 Applying Logstash..."
kubectl apply -f logstash.yaml

# Apply Filebeat (Legacy)
echo "    🚀 Applying Filebeat..."
kubectl apply -f filebeat.yaml

# Apply Ingress (Renamed from ingress.yaml)
echo "    🚀 Applying Kibana/ES Ingress..."
kubectl apply -f kibana-ingress.yaml

# 3. Wait for Rollout (Elasticsearch first)
echo " [3] Verifying Rollout Status..."
echo "    ⏳ Waiting for Elasticsearch (oci-logs)..."
if kubectl -n elastic-system rollout status elasticsearch/oci-logs --timeout=300s; then
    echo "    ✅ Elasticsearch is Ready."
else
    echo "    ⚠️  Elasticsearch timed out. Checking Operator logs..."
    kubectl -n elastic-system logs -l control-plane=elastic-operator --tail=20 || true
fi

echo "    ⏳ Waiting for Logstash (oci-logstash)..."
if kubectl -n elastic-system rollout status statefulset/oci-logstash-ls --timeout=300s; then
    echo "    ✅ Logstash is Ready."
else
    echo "    ⚠️  Logstash timed out."
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
