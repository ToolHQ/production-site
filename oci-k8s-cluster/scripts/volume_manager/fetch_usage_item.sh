#!/bin/bash
# fetch_usage_item.sh
# Fetches USED and USAGE% for a single PVC
# Usage: ./fetch_usage_item.sh <namespace> <pvc_name>
# Output: USED|USAGE (e.g. "500Mi|45%" or "N/A|N/A")

NS=$1
PVC=$2

if [ -z "$NS" ] || [ -z "$PVC" ]; then
    echo "N/A|N/A"
    exit 1
fi

# SSH wrapper (local definition to be standalone)
k_exec() {
    ssh -o ConnectTimeout=5 -o ServerAliveInterval=5 -q oci-k8s-master "$@"
}

# Get ALL pods (for display)
ALL_PODS_RAW=$(k_exec "kubectl get pods -n $NS -o json 2>/dev/null" | jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$PVC\") | .metadata.name" 2>/dev/null)

# Use first pod for metrics execution
POD=$(echo "$ALL_PODS_RAW" | head -1)

# Format list for display (newline to comma + space)
ALL_PODS_DISPLAY=$(echo "$ALL_PODS_RAW" | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')

if [ -z "$POD" ]; then
    echo "N/A|N/A|N/A|N/A|N/A|${STORAGE_CLASS}|N/A"
    exit 0
fi

# 2. Get Volume Name and Mount Path
VOL_INFO=$(k_exec "kubectl get pod $POD -n $NS -o json 2>/dev/null" | jq -r ".spec.volumes[] | select(.persistentVolumeClaim.claimName == \"$PVC\") | .name" 2>/dev/null)

if [ -z "$VOL_INFO" ]; then
    echo "N/A|N/A|N/A|N/A|N/A|Standard|N/A"
    exit 0
fi

# 3. Get Container and Mount Path
MOUNT_INFO=$(k_exec "kubectl get pod $POD -n $NS -o json 2>/dev/null" | jq -r ".spec.containers[] | select(.volumeMounts[]?.name == \"$VOL_INFO\") | .name + \"|\" + (.volumeMounts[] | select(.name == \"$VOL_INFO\") | .mountPath)" 2>/dev/null | head -1)

if [ -z "$MOUNT_INFO" ]; then
    echo "N/A|N/A|N/A|N/A|N/A|Standard|N/A"
    exit 0
fi

CONTAINER_NAME=$(echo "$MOUNT_INFO" | cut -d"|" -f1)
MOUNT_PATH=$(echo "$MOUNT_INFO" | cut -d"|" -f2)

# 4. Check Storage Class (hostPath vs Longhorn/Standard)
STORAGE_CLASS=$(k_exec "kubectl get pvc $PVC -n $NS -o jsonpath=\"{.spec.storageClassName}\"" 2>/dev/null)

USED="N/A"
USAGE="N/A"

if [ "$STORAGE_CLASS" = "manual" ] || [ "$STORAGE_CLASS" = "hostpath" ]; then
    # hostPath: Use du
    DU_OUT=$(k_exec "kubectl exec -n $NS $POD -c $CONTAINER_NAME -- du -sh $MOUNT_PATH 2>/dev/null" 2>/dev/null | head -1 | awk '{print $1}')
    if [ -n "$DU_OUT" ]; then
        USED=$(echo "$DU_OUT" | sed "s/^\([0-9.]*\)\([KMGT]\)$/\1\2i/")
        USAGE="N/A" # No quota on hostPath usually
    fi
else
    # Standard/Longhorn: Use df -P -k (POSIX, 1K blocks) to avoid wrapping and get raw numbers
    # grep for mount path at end of line to ensure we match the correct line
    DF_OUT=$(k_exec "kubectl exec -n $NS $POD -c $CONTAINER_NAME -- df -P -k 2>/dev/null" 2>/dev/null | grep " $MOUNT_PATH\$")
    
    if [ -n "$DF_OUT" ]; then
        # Parse raw blocks (1K units)
        # $2 = Total, $3 = Used
        # Return: HUMAND_READABLE_USED|PERCENTAGE
        
        STATS=$(echo "$DF_OUT" | awk '{
            used_k = $3;
            total_k = $2;
            
            # Formatting Human Readable (simulating df -h but with Ki/Mi/Gi)
            human_used = "";
            if (used_k < 1024) {
                 human_used = sprintf("%.0fKi", used_k);
            } else {
                 used_m = used_k / 1024;
                 if (used_m < 1024) {
                     human_used = sprintf("%.1fMi", used_m);
                 } else {
                     used_g = used_m / 1024;
                     human_used = sprintf("%.1fGi", used_g);
                 }
            }
            
            # Calculate Percentage with 2 decimal places
            if (total_k > 0) {
                pct = (used_k / total_k) * 100;
                printf "%s|%.2f%%", human_used, pct;
            } else {
                printf "%s|N/A", human_used;
            }
        }')
        
        USED=$(echo "$STATS" | cut -d'|' -f1)
        USAGE=$(echo "$STATS" | cut -d'|' -f2)
    fi
fi

# Ensure defaults
USED=${USED:-N/A}
USAGE=${USAGE:-N/A}
POD=${POD:-N/A}
CONTAINER_NAME=${CONTAINER_NAME:-N/A}
MOUNT_PATH=${MOUNT_PATH:-N/A}
# 5. Get Access Mode
ACCESS_MODE=$(k_exec "kubectl get pvc $PVC -n $NS -o jsonpath=\"{.spec.accessModes[0]}\"" 2>/dev/null)

# Ensure defaults
USED=${USED:-N/A}
USAGE=${USAGE:-N/A}
POD=${POD:-N/A}
CONTAINER_NAME=${CONTAINER_NAME:-N/A}
MOUNT_PATH=${MOUNT_PATH:-N/A}
STORAGE_CLASS=${STORAGE_CLASS:-standard}
ALL_PODS_DISPLAY=${ALL_PODS_DISPLAY:-$POD}
ACCESS_MODE=${ACCESS_MODE:-N/A}

# Output format: USED|USAGE|POD|CONTAINER|MOUNT_PATH|STORAGE_CLASS|ALL_PODS|ACCESS_MODE
echo "${USED}|${USAGE}|${POD}|${CONTAINER_NAME}|${MOUNT_PATH}|${STORAGE_CLASS}|${ALL_PODS_DISPLAY}|${ACCESS_MODE}"
