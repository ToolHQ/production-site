#!/bin/bash
# List all PVCs with REAL usage statistics (optimized with caching)
# Part of T-017: TUI Volume Manager

set -e

# Cache file for pod-to-mount mapping
CACHE_FILE="/tmp/pvc_usage_cache_$$"
trap "rm -f $CACHE_FILE" EXIT

# Normalize size units
normalize_size() {
    local size=$1
    if [[ "$size" =~ ^([0-9.]+)([KMGT])$ ]]; then
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}i"
    else
        echo "$size"
    fi
}

# Format percentage with 1 decimal
format_percentage() {
    local pct=$1
    local num=$(echo "$pct" | tr -d '%')
    if [[ "$num" =~ ^[0-9.]+$ ]]; then
        printf "%.1f%%" "$num"
    else
        echo "$pct"
    fi
}

# Get usage for a specific PVC (with pod info)
get_pvc_usage() {
    local namespace=$1
    local pvc_name=$2
    
    # Find pod using this PVC
    local pod=$(ssh oci-k8s-master "kubectl get pods -n $namespace -o json 2>/dev/null" | \
                jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$pvc_name\") | .metadata.name" 2>/dev/null | head -1)
    
    if [ -z "$pod" ]; then
        echo "N/A|N/A|0.0%"
        return
    fi
    
    # Try to get df output from pod
    local df_output=""
    for mount in "/data" "/var/lib/postgresql" "/usr/share/elasticsearch/data" "/nexus-data" "/var/lib/mysql" "/usr/share/logstash" "/var/lib/prometheus" "/prometheus"; do
        df_output=$(ssh oci-k8s-master "kubectl exec -n $namespace $pod -c \$(kubectl get pod $pod -n $namespace -o jsonpath='{.spec.containers[0].name}' 2>/dev/null) -- df -h $mount 2>/dev/null" 2>/dev/null | grep -E '^/dev|^overlay' | head -1)
        
        if [ -n "$df_output" ]; then
            local used=$(echo "$df_output" | awk '{print $3}')
            local available=$(echo "$df_output" | awk '{print $4}')
            local usage_pct=$(echo "$df_output" | awk '{print $5}')
            
            # Normalize and format
            used=$(normalize_size "$used")
            available=$(normalize_size "$available")
            usage_pct=$(format_percentage "$usage_pct")
            
            echo "$used|$available|$usage_pct"
            return
        fi
    done
    
    echo "N/A|N/A|0.0%"
}

# Main output header
echo "NAMESPACE|PVC_NAME|ALLOCATED|USED|AVAILABLE|USAGE_PCT|STATUS|STORAGECLASS"

# Get all PVCs and their usage
ssh oci-k8s-master "kubectl get pvc -A -o json 2>/dev/null" | jq -r '
    .items[] | 
    "\(.metadata.namespace)|\(.metadata.name)|\(.status.capacity.storage // "N/A")|\(.status.phase)|\(.spec.storageClassName)"
' 2>/dev/null | while IFS='|' read -r namespace pvc_name allocated status storageclass; do
    
    # Get actual usage (this is the slow part, but necessary for accuracy)
    usage_info=$(get_pvc_usage "$namespace" "$pvc_name")
    
    echo "$namespace|$pvc_name|$allocated|$usage_info|$status|$storageclass"
done
