#!/bin/bash
# List all PVCs with usage statistics
# Part of T-017: TUI Volume Manager

set -e

# Output format: NAMESPACE|PVC_NAME|ALLOCATED|USED|AVAILABLE|USAGE_PCT|STATUS|STORAGECLASS|AGE
list_all_pvcs() {
    ssh oci-k8s-master "kubectl get pvc -A -o json" | jq -r '
        .items[] | 
        "\(.metadata.namespace)|\(.metadata.name)|\(.status.capacity.storage // "N/A")|\(.status.phase)|\(.spec.storageClassName)|\(.metadata.creationTimestamp)"
    '
}

# Get actual disk usage for a specific PVC
get_pvc_usage() {
    local namespace=$1
    local pvc_name=$2
    
    # Find pod using this PVC
    local pod=$(ssh oci-k8s-master "kubectl get pods -n $namespace -o json" | \
                jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$pvc_name\") | .metadata.name" | head -1)
    
    if [ -z "$pod" ]; then
        echo "N/A|N/A|N/A"
        return
    fi
    
    # Try common mount points
    for mount in "/data" "/var/lib/postgresql" "/usr/share/elasticsearch/data" "/nexus-data" "/var/lib/mysql"; do
        local df_output=$(ssh oci-k8s-master "kubectl exec -n $namespace $pod -- df -h $mount 2>/dev/null" | tail -1 || echo "")
        
        if [ -n "$df_output" ]; then
            local used=$(echo $df_output | awk '{print $3}')
            local available=$(echo $df_output | awk '{print $4}')
            local usage_pct=$(echo $df_output | awk '{print $5}')
            echo "$used|$available|$usage_pct"
            return
        fi
    done
    
    echo "N/A|N/A|N/A"
}

# Main output
echo "NAMESPACE|PVC_NAME|ALLOCATED|USED|AVAILABLE|USAGE_PCT|STATUS|STORAGECLASS|AGE"

while IFS='|' read -r namespace pvc_name allocated status storageclass age; do
    # Get actual usage
    usage_info=$(get_pvc_usage "$namespace" "$pvc_name")
    
    echo "$namespace|$pvc_name|$allocated|$usage_info|$status|$storageclass|$age"
done < <(list_all_pvcs)
