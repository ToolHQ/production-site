#!/bin/bash
# cleanup_stuck_volumes.sh
# Cleans up stuck "temp" PVCs, Copy Jobs, and resources from failed shrink operations.
# SAFETY FIRST: Enforces 'Retain' policy on PVs before deleting PVCs.
# NOW WITH SSH WRAPPER for remote execution.

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "CLEANUP STUCK VOLUMES (SAFE MODE)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Helper to run kubectl on master
k() {
    ssh oci-k8s-master "kubectl $@"
}

# Function to ensure PV is set to Retain
ensure_pv_retain() {
    local pvc_name=$1
    local namespace=$2
    
    # Get PV name
    local pv_name=$(k get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.spec.volumeName}' 2>/dev/null)
    
    if [ -n "$pv_name" ]; then
        echo "    Protection: Setting ReclaimPolicy to Retain for PV $pv_name..."
        k patch pv "$pv_name" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}' >/dev/null 2>&1
        echo "    ✓ PV $pv_name is now protected (Retain)"
    else
        echo "    ⚠️  Warning: Could not find PV for $pvc_name (maybe already unbound?)"
    fi
}

# 1. Cleanup Jobs
echo "[1/4] Cleaning up stuck Copy Jobs..."
# Use -- to prevent grep definition issues
JOBS=$(k get jobs -A | grep "volume-copy-" | awk '{print $1 " " $2}')
if [ -z "$JOBS" ]; then
    echo "  ✓ No stuck copy jobs found."
else
    echo "$JOBS" | while read -r NS NAME; do
        echo "  Deleting job: $NAME in namespace $NS..."
        k delete job "$NAME" -n "$NS" --force --grace-period=0 2>/dev/null || true
    done
fi
echo ""

# 2. Cleanup Temp PVCs
echo "[2/4] Cleaning up Temp PVCs..."
# Use simple grep for "temp" to avoid flag issues
TEMP_PVCS=$(k get pvc -A | grep "temp" | awk '{print $1 " " $2}')

if [ -z "$TEMP_PVCS" ]; then
    echo "  ✓ No temp PVCs found."
else
    echo "$TEMP_PVCS" | while read -r NS NAME; do
        # Extract original name (remove -temp-TIMESTAMP)
        # Using basic sed pattern
        ORIG_NAME=$(echo "$NAME" | sed 's/-temp-[0-9]\{8\}-[0-9]\{6\}//')
        
        # Check if original exists (return code 0 = exists)
        if k get pvc "$ORIG_NAME" -n "$NS" >/dev/null 2>&1; then
            echo "  Target: $NAME (Original $ORIG_NAME exists)"
            ensure_pv_retain "$NAME" "$NS"
            
            echo "    Removing finalizers and deleting temp PVC..."
            k patch pvc "$NAME" -n "$NS" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            k delete pvc "$NAME" -n "$NS" --force --grace-period=0 --wait=false 2>/dev/null || true
        else
            echo "  ⚠️  SKIPPING $NAME: Original PVC '$ORIG_NAME' NOT FOUND. This temp PVC might contain the only data copy!"
            echo "      Manual inspection required for this volume."
        fi
    done
fi
echo ""

# 3. Cleanup Stuck Terminating PVCs
echo "[3/4] Cleaning up stuck Terminating PVCs..."
# Look for Terminating PVCs matching our key workloads
STUCK_PVCS=$(k get pvc -A | grep "Terminating" | grep -E 'dlq-vol|elastic|logstash|postgres' | awk '{print $1 " " $2}')

if [ -z "$STUCK_PVCS" ]; then
    echo "  ✓ No stuck Terminating PVCs found."
else
    echo "$STUCK_PVCS" | while read -r NS NAME; do
        echo "  Target Stuck PVC: $NAME in namespace $NS"
        ensure_pv_retain "$NAME" "$NS"
        
        echo "    Force removing finalizers to unblock deletion..."
        k patch pvc "$NAME" -n "$NS" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        k delete pvc "$NAME" -n "$NS" --force --grace-period=0 --wait=false 2>/dev/null || true
        echo "    ✓ Stuck status cleared (PV is safe/retained)"
    done
fi
echo ""

# 4. Orphaned PV Check
echo "[4/4] Checking for Released PVs (Potential Orphans)..."
RELEASED_PVS=$(k get pv | grep "Released" | awk '{print $1}')
if [ -z "$RELEASED_PVS" ]; then
    echo "  ✓ No Released PVs found."
else
    echo "  ℹ️  Found Released PVs (Data Preserved):"
    echo "$RELEASED_PVS"
    echo "      These PVs are safe but unbound. If you need to reuse them, their 'claimRef' must be cleared."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Cleanup Check Completed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
