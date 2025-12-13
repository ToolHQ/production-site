#!/bin/bash
# vm_utils.sh
# Shared utilities for Volume Manager scripts

# SSH wrapper for kubectl on master
k() {
    ssh oci-k8s-master "kubectl $@"
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
        k patch pv "$pv_name" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}' >/dev/null 2>&1
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
        k patch pv "$pv_name" -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}' >/dev/null 2>&1
        log "✓ PV policy restored to Delete."
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
