#!/bin/bash
# Storage Audit Script - Check actual usage of all PVCs
# T-016: Storage Optimization Audit

echo "=== STORAGE AUDIT REPORT ==="
echo "Generated: $(date)"
echo ""
echo "| Namespace | PVC Name | Allocated | Used | Available | Usage % | Waste |"
echo "|-----------|----------|-----------|------|-----------|---------|-------|"

# Function to check PVC usage
check_pvc_usage() {
    local namespace=$1
    local pvc_name=$2
    local allocated=$3
    
    # Find pod using this PVC
    pod=$(ssh oci-k8s-master "kubectl get pods -n $namespace -o json" | \
          jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$pvc_name\") | .metadata.name" | head -1)
    
    if [ -z "$pod" ]; then
        echo "| $namespace | $pvc_name | $allocated | N/A | N/A | N/A | No pod found |"
        return
    fi
    
    # Get mount point from pod spec
    mount_point=$(ssh oci-k8s-master "kubectl get pod $pod -n $namespace -o json" | \
                  jq -r ".spec.containers[0].volumeMounts[] | select(.name | contains(\"$pvc_name\") or contains(\"data\") or contains(\"storage\")) | .mountPath" | head -1)
    
    if [ -z "$mount_point" ]; then
        mount_point="/data"  # Default fallback
    fi
    
    # Get df output
    df_output=$(ssh oci-k8s-master "kubectl exec -n $namespace $pod -- df -h $mount_point 2>/dev/null" | tail -1)
    
    if [ -z "$df_output" ]; then
        echo "| $namespace | $pvc_name | $allocated | N/A | N/A | N/A | Cannot exec |"
        return
    fi
    
    used=$(echo $df_output | awk '{print $3}')
    available=$(echo $df_output | awk '{print $4}')
    usage_pct=$(echo $df_output | awk '{print $5}')
    
    # Calculate waste (simple heuristic: if usage < 50%, consider it over-provisioned)
    usage_num=$(echo $usage_pct | tr -d '%')
    if [ "$usage_num" -lt 50 ]; then
        waste="⚠️ Over-provisioned"
    else
        waste="✅ OK"
    fi
    
    echo "| $namespace | $pvc_name | $allocated | $used | $available | $usage_pct | $waste |"
}

# Elasticsearch
check_pvc_usage "elastic-system" "elasticsearch-data-oci-logs-es-default-0" "5Gi"
check_pvc_usage "elastic-system" "elasticsearch-data-oci-logs-es-default-1" "5Gi"
check_pvc_usage "elastic-system" "logstash-data-oci-logstash-ls-0" "1Gi"
check_pvc_usage "elastic-system" "dlq-vol-oci-logstash-ls-0" "2Gi"

# Kubecost
check_pvc_usage "kubecost" "kubecost-cost-analyzer" "5Gi"
check_pvc_usage "kubecost" "kubecost-prometheus-server" "5Gi"

# Nexus
check_pvc_usage "nexus" "nexus-pvc" "10Gi"

# Postgres
check_pvc_usage "postgres" "postgres-pvc" "5Gi"

# MinIO
check_pvc_usage "minio" "minio-pvc" "1Gi"

echo ""
echo "=== SUMMARY ==="
echo "Total Allocated: ~44Gi"
echo "Recommendation: Review volumes marked with ⚠️ for downsizing"
