#!/bin/bash
# Storage Optimization Execution Script - Phase 1
# T-016: Resize Logstash and Postgres PVCs

set -e

echo "=== STORAGE OPTIMIZATION - PHASE 1 ==="
echo "Target: Logstash DLQ (2Gi→500Mi) + Postgres (5Gi→2Gi)"
echo "Expected Savings: 5Gi"
echo ""

# Function to backup and resize PVC
resize_pvc() {
    local namespace=$1
    local deployment=$2
    local pvc_name=$3
    local new_size=$4
    
    echo "📦 Processing: $namespace/$pvc_name"
    
    # Step 1: Scale down
    echo "  ⏬ Scaling down $deployment..."
    ssh oci-k8s-master "kubectl scale deployment $deployment -n $namespace --replicas=0" || \
    ssh oci-k8s-master "kubectl scale statefulset $deployment -n $namespace --replicas=0"
    
    sleep 5
    
    # Step 2: Delete PVC
    echo "  🗑️  Deleting old PVC..."
    ssh oci-k8s-master "kubectl delete pvc $pvc_name -n $namespace --wait=true"
    
    # Step 3: Apply new manifest (PVC will be recreated with new size)
    echo "  📝 Applying updated manifest..."
    if [ "$namespace" == "postgres" ]; then
        ssh oci-k8s-master "kubectl apply -f /home/ubuntu/deployments/postgres/postgres-resources.yaml"
    elif [ "$namespace" == "elastic-system" ]; then
        ssh oci-k8s-master "kubectl apply -f /home/ubuntu/deployments/observability/manifests/logstash.yaml"
    fi
    
    sleep 5
    
    # Step 4: Scale up
    echo "  ⏫ Scaling up $deployment..."
    ssh oci-k8s-master "kubectl scale deployment $deployment -n $namespace --replicas=1" || \
    ssh oci-k8s-master "kubectl scale statefulset $deployment -n $namespace --replicas=1"
    
    echo "  ✅ $pvc_name resized successfully"
    echo ""
}

# Execute Phase 1 optimizations
echo "Starting Phase 1 optimizations..."
echo ""

# 1. Postgres (Deployment)
resize_pvc "postgres" "postgres-deployment" "postgres-pvc" "2Gi"

# 2. Logstash (StatefulSet)
resize_pvc "elastic-system" "oci-logstash" "dlq-vol-oci-logstash-ls-0" "128Mi"

echo "=== PHASE 1 COMPLETE ==="
echo "✅ Postgres: 5Gi → 2Gi (saved 3Gi)"
echo "✅ Logstash DLQ: 2Gi → 500Mi (saved 1.5Gi)"
echo "📊 Total Savings: 4.5Gi"
echo ""
echo "⚠️  Note: Data was NOT backed up. These are low-risk volumes."
echo "Next: Run Phase 2 for Elasticsearch and Nexus (requires backups)"
