#!/bin/bash
set -e

# uninstall_commands.sh for Elastic Stack
# Executed by deploy_components.sh during Uninstallation

echo "🗑️  Starting Elastic Stack Uninstallation..."

# 1. Delete Kibana & Ingress
echo " [1] Deleting Kibana & Ingress..."
if kubectl get ingress -n elastic-system elastic-stack-ingress &>/dev/null; then
    kubectl delete ingress -n elastic-system elastic-stack-ingress
fi
if kubectl get kibana -n elastic-system oci-logs &>/dev/null; then
    kubectl delete kibana -n elastic-system oci-logs
fi

# 2. Delete Logstash & Filebeat
echo " [2] Deleting Logstash & Filebeat..."
if kubectl get logstash -n elastic-system oci-logstash &>/dev/null; then
    kubectl delete logstash -n elastic-system oci-logstash
fi
if kubectl get beat -n elastic-system oci-filebeat &>/dev/null; then
    kubectl delete beat -n elastic-system oci-filebeat
fi

# 3. Delete Elasticsearch
echo " [3] Deleting Elasticsearch..."
if kubectl get elasticsearch -n elastic-system oci-logs &>/dev/null; then
    kubectl delete elasticsearch -n elastic-system oci-logs
fi

# 4. Cleanup PVCs (Longhorn)
echo " [4] Cleaning up Storage (PVCs)..."
# We aggressively clean up PVCs for a true 'uninstall'
kubectl -n elastic-system delete pvc -l common.k8s.elastic.co/type=elasticsearch --wait=false 2>/dev/null || true
kubectl -n elastic-system delete pvc -l common.k8s.elastic.co/type=logstash --wait=false 2>/dev/null || true

# 5. ECK Operator
echo " [5] Removing ECK Operator..."
kubectl delete -f https://download.elastic.co/downloads/eck/2.10.0/operator.yaml --ignore-not-found=true

# 6. ECK CRDs (Custom Resource Definitions)
echo " [6] Removing ECK CRDs..."
kubectl delete -f https://download.elastic.co/downloads/eck/2.10.0/crds.yaml --ignore-not-found=true

echo "✅ Elastic Stack resources, Operator, and CRDs removed."
echo "   (Namespace 'elastic-system' preserved just in case)"
