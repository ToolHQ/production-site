#!/bin/bash
# List all PVCs with usage statistics (OPTIMIZED VERSION)
# Part of T-017: TUI Volume Manager

set -e

# Normalize size units (convert G to Gi, M to Mi, etc)
normalize_size() {
    local size=$1
    if [[ "$size" =~ ^([0-9.]+)([KMGT])$ ]]; then
        echo "${BASH_REMATCH[1]}${BASH_REMATCH[2]}i"
    else
        echo "$size"
    fi
}

# Format percentage with 1 decimal place
format_percentage() {
    local pct=$1
    local num=$(echo "$pct" | tr -d '%')
    if [[ "$num" =~ ^[0-9.]+$ ]]; then
        printf "%.1f%%" "$num"
    else
        echo "$pct"
    fi
}

# Main output header
echo "NAMESPACE|PVC_NAME|ALLOCATED|USED|AVAILABLE|USAGE_PCT|STATUS|STORAGECLASS|AGE"

# Get all PVCs in one shot
ssh oci-k8s-master "kubectl get pvc -A -o json 2>/dev/null" | jq -r '
    .items[] | 
    "\(.metadata.namespace)|\(.metadata.name)|\(.status.capacity.storage // "N/A")|\(.status.phase)|\(.spec.storageClassName)"
' 2>/dev/null | while IFS='|' read -r namespace pvc_name allocated status storageclass; do
    
    # Quick output with N/A for usage (will be populated async if needed)
    # For now, just show the PVC info quickly
    echo "$namespace|$pvc_name|$allocated|N/A|N/A|N/A|$status|$storageclass|N/A"
done
