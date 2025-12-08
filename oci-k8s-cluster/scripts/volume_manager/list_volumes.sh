#!/bin/bash
# List all PVCs with usage statistics
# Part of T-017: TUI Volume Manager

set -e

# Normalize size units (convert G to Gi, M to Mi, etc)
normalize_size() {
    local size=$1
    # If size ends with just G, M, K (no 'i'), add 'i'
    if [[ "$size" =~ ^([0-9.]+)([KMGT])$ ]]; then
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}i"
    else
        echo "$size"
    fi
}

# Format percentage with 1 decimal place
format_percentage() {
    local pct=$1
    # Remove % sign and format
    local num=$(echo "$pct" | tr -d '%')
    if [[ "$num" =~ ^[0-9]+$ ]]; then
        printf "%.1f%%" "$num"
    else
        echo "$pct"
    fi
}

# Get actual disk usage for a specific PVC
get_pvc_usage() {
    local namespace=$1
    local pvc_name=$2
    
    # Find pod using this PVC
    local pod=$(ssh oci-k8s-master "kubectl get pods -n $namespace -o json 2>/dev/null" | \
                jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$pvc_name\") | .metadata.name" 2>/dev/null | head -1)
    
    if [ -z "$pod" ]; then
        echo "N/A|N/A|N/A"
        return
    fi
    
    # Try common mount points
    for mount in "/data" "/var/lib/postgresql" "/usr/share/elasticsearch/data" "/nexus-data" "/var/lib/mysql" "/usr/share/logstash" "/var/lib/prometheus"; do
        local df_output=$(ssh oci-k8s-master "kubectl exec -n $namespace $pod -- df -h $mount 2>/dev/null" 2>/dev/null | tail -1)
        
        if [ -n "$df_output" ] && [[ "$df_output" != *"No such file"* ]] && [[ "$df_output" =~ ^/dev ]]; then
            local used=$(echo "$df_output" | awk '{print $3}')
            local available=$(echo "$df_output" | awk '{print $4}')
            local usage_pct=$(echo "$df_output" | awk '{print $5}')
            
            # Normalize units and format percentage
            used=$(normalize_size "$used")
            available=$(normalize_size "$available")
            usage_pct=$(format_percentage "$usage_pct")
            
            echo "$used|$available|$usage_pct"
            return
        fi
    done
    
    echo "N/A|N/A|N/A"
}

# Main output
echo "NAMESPACE|PVC_NAME|ALLOCATED|USED|AVAILABLE|USAGE_PCT|STATUS|STORAGECLASS|AGE"

# Get all PVCs
ssh oci-k8s-master "kubectl get pvc -A -o json 2>/dev/null" | jq -r '
    .items[] | 
    "\(.metadata.namespace)|\(.metadata.name)|\(.status.capacity.storage // "N/A")|\(.status.phase)|\(.spec.storageClassName)|\(.metadata.creationTimestamp)"
' 2>/dev/null | while IFS='|' read -r namespace pvc_name allocated status storageclass age; do
    # Get actual usage
    usage_info=$(get_pvc_usage "$namespace" "$pvc_name")
    
    echo "$namespace|$pvc_name|$allocated|$usage_info|$status|$storageclass|$age"
done
