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
    # Standard/Longhorn: Use df
    # grep for mount path at end of line to ensure we match the correct line
    DF_OUT=$(k_exec "kubectl exec -n $NS $POD -c $CONTAINER_NAME -- df -h 2>/dev/null" 2>/dev/null | grep " $MOUNT_PATH\$")
    
    if [ -n "$DF_OUT" ]; then
        # Handle wrapped df output common in k8s (Long filesystem names wrap to next line)
        # Normal:   Filesystem Size Used Avail Use% Mounted on (6 fields)
        # Wrapped:             Size Used Avail Use% Mounted on (5 fields)
        
        NUM_FIELDS=$(echo "$DF_OUT" | awk '{print NF}')
        
        if [ "$NUM_FIELDS" -eq 6 ]; then
            RAW_USED=$(echo "$DF_OUT" | awk '{print $3}')
            PCT=$(echo "$DF_OUT" | awk '{print $5}')
        elif [ "$NUM_FIELDS" -eq 5 ]; then
            RAW_USED=$(echo "$DF_OUT" | awk '{print $2}')
            PCT=$(echo "$DF_OUT" | awk '{print $4}')
        else
            # Unexpected format, try to find % field
            PCT=$(echo "$DF_OUT" | grep -o "[0-9]*%")
            RAW_USED="N/A"
        fi
        
        USED=$(echo "$RAW_USED" | sed "s/^\([0-9.]*\)\([KMGT]\)$/\1\2i/")
        USAGE="$PCT"
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
