#!/bin/bash
# vm_utils.sh
# Shared utilities for Volume Manager scripts

# SSH wrapper for kubectl on master
# SSH wrapper for kubectl on master (with Retry)
k() {
    local max_attempts=3
    local attempt=1
    local status=0
    
    while [ $attempt -le $max_attempts ]; do
        ssh -o ConnectTimeout=10 -o ServerAliveInterval=5 oci-k8s-master "kubectl $@"
        status=$?
        
        # If success (0) or application error (1), return immediately.
        # OpenSSH returns 255 for connection errors.
        if [ $status -ne 255 ]; then
            return $status
        fi
        
        # If connection error, retry
        if [ $attempt -lt $max_attempts ]; then
            echo "⚠️  SSH failed (Code: $status). Retrying ($attempt/$max_attempts)..." >&2
            sleep 2
        fi
        attempt=$((attempt + 1))
    done
    
    return $status
}

log() {
    echo "   $1"
}

header() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Protect PV by setting ReclaimPolicy to Retain
# Usage: protect_pv <namespace> <pvc_name>
protect_pv() {
    local ns=$1
    local pvc_name=$2
    
    local pv_name=$(k get pvc "$pvc_name" -n "$ns" -o jsonpath='{.spec.volumeName}' 2>/dev/null)
    
    if [ -n "$pv_name" ]; then
        log "Protecting PV $pv_name (Retain)..."
        # Escape quotes for SSH transmission: '{"spec":...}' -> '{\"spec\":...}'
        if ! OUTPUT=$(k patch pv "$pv_name" -p '{\"spec\":{\"persistentVolumeReclaimPolicy\":\"Retain\"}}' 2>&1); then
            log "✗ Error protecting PV: $OUTPUT"
            return 1
        fi
        return 0
    else
        log "⚠️  Warning: Could not find PV for $pvc_name (maybe already unbound?)"
        return 1
    fi
}

# Restore PV ReclaimPolicy to Delete
# Usage: restore_pv_policy <pv_name>
restore_pv_policy() {
    local pv_name=$1
    if [ -n "$pv_name" ]; then
        if ! OUTPUT=$(k patch pv "$pv_name" -p '{\"spec\":{\"persistentVolumeReclaimPolicy\":\"Delete\"}}' 2>&1); then
            log "⚠️  Warning: Failed to restore PV policy: $OUTPUT"
        else
            log "✓ PV policy restored to Delete."
        fi
    fi
}

# Create a snapshot of a PVC
# Usage: snapshot_pvc <namespace> <pvc_name>
snapshot_pvc() {
    local ns=$1
    local pvc=$2
    local snap_name="${pvc}-snap-$(date +%Y%m%d-%H%M%S)"
    log "Creating snapshot $snap_name..."
    cat <<EOF | k apply -f - >/dev/null
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $snap_name
  namespace: $ns
spec:
  volumeSnapshotClassName: longhorn-snapshot-vsc
  source:
    persistentVolumeClaimName: $pvc
EOF
    log "✓ Snapshot created."
}
