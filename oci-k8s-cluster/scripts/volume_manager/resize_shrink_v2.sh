#!/bin/bash
# Volume Shrink v2 - Copy-based strategy (IMPROVED)
# Safer approach: Create new volume, copy data, swap volumes
# Uses vm_utils.sh for shared logic.

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm_utils.sh"

NAMESPACE=$1
PVC_NAME=$2
NEW_SIZE=$3
DEPLOYMENT=$4

if [ -z "$NAMESPACE" ] || [ -z "$PVC_NAME" ] || [ -z "$NEW_SIZE" ] || [ -z "$DEPLOYMENT" ]; then
    echo "Usage: $0 <namespace> <pvc-name> <new-size> <deployment>"
    exit 1
fi

header "SHRINK VOLUME - Copy-based Strategy v2"
echo "Namespace:   $NAMESPACE"
echo "PVC:         $PVC_NAME"
echo "New Size:    $NEW_SIZE"
echo "Deployment:  $DEPLOYMENT"
echo ""

# Cleanup function for rollback
cleanup_on_error() {
    echo ""
    log "⚠️  ERROR DETECTED - Attempting cleanup..."
    
    # Scale deployment back up
    log "Scaling deployment back to 1..."
    k scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=1 2>/dev/null || \
    k scale statefulset $DEPLOYMENT -n $NAMESPACE --replicas=1 2>/dev/null || true
    
    # Delete temp PVC if exists
    if [ -n "$TEMP_PVC" ]; then
        log "Deleting temporary PVC: $TEMP_PVC"
        k delete pvc $TEMP_PVC -n $NAMESPACE --force --grace-period=0 2>/dev/null || true
    fi
    
    # Delete job if exists
    if [ -n "$JOB_NAME" ]; then
        log "Deleting copy job: $JOB_NAME"
        k delete job $JOB_NAME -n $NAMESPACE 2>/dev/null || true
    fi
    
    log "✓ Cleanup completed"
    exit 1
}

trap cleanup_on_error ERR

# Get current PVC info
echo "[1/9] Getting current PVC information..."
STORAGE_CLASS=$(k get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.storageClassName}')
ACCESS_MODE=$(k get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.accessModes[0]}')
CURRENT_SIZE=$(k get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}')

echo "  Current Size:    $CURRENT_SIZE"
echo "  Storage Class:   $STORAGE_CLASS"
echo "  Access Mode:     $ACCESS_MODE"
echo ""

# Scale down deployment
echo "[2/9] Scaling down deployment to 0..."
k scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=0 2>/dev/null || \
k scale statefulset $DEPLOYMENT -n $NAMESPACE --replicas=0
echo "  ✓ Deployment scaled to 0"
echo ""

# Wait for pod termination
echo "[3/9] Waiting for pod termination..."
sleep 5

# Check for any pods using this PVC (more robust than label selector)
for i in {1..90}; do
    POD_COUNT=$(k get pods -n $NAMESPACE -o json 2>/dev/null | jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$PVC_NAME\") | .metadata.name" | wc -l)
    
    if [ "$POD_COUNT" -eq 0 ]; then
        echo "  ✓ All pods using $PVC_NAME terminated"
        break
    fi
    echo "  Waiting for $POD_COUNT pods using $PVC_NAME to terminate... ($i/90)"
    sleep 2
done

# Force delete if still running after timeout
if [ "$POD_COUNT" -ne 0 ]; then
    echo "  ⚠️  Pods taking too long to terminate. forcing..."
    # Get the pod names
    PODS=$(k get pods -n $NAMESPACE -o json 2>/dev/null | jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$PVC_NAME\") | .metadata.name")
    for POD in $PODS; do
        echo "  Deleting pod $POD..."
        k delete pod $POD -n $NAMESPACE --force --grace-period=0 2>/dev/null || true
    done
fi

echo ""

# Create temporary PVC
TEMP_PVC="${PVC_NAME}-temp-$(date +%Y%m%d-%H%M%S)"
echo "[4/9] Creating temporary PVC: $TEMP_PVC"

cat <<EOF | k apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $TEMP_PVC
  namespace: $NAMESPACE
spec:
  accessModes:
    - $ACCESS_MODE
  storageClassName: $STORAGE_CLASS
  resources:
    requests:
      storage: $NEW_SIZE
EOF

echo "  ✓ Temporary PVC created"
echo ""

# Wait for PVC to be bound
echo "[5/9] Waiting for temporary PVC to be bound..."
for i in {1..30}; do
    STATUS=$(k get pvc $TEMP_PVC -n $NAMESPACE -o jsonpath='{.status.phase}')
    if [ "$STATUS" = "Bound" ]; then
        echo "  ✓ Temporary PVC is Bound"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
done

if [ "$STATUS" != "Bound" ]; then
    echo "  ✗ ERROR: Temporary PVC failed to bind"
    exit 1
fi
echo ""

# Create copy job
echo "[6/9] Creating data copy job..."
JOB_NAME="volume-copy-$(date +%Y%m%d-%H%M%S)"

cat <<EOF | k apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB_NAME
  namespace: $NAMESPACE
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: copy
        image: alpine:latest
        command:
        - sh
        - -c
        - |
          apk add --no-cache rsync
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "Starting data copy with rsync..."
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          # Use rsync with progress2 for total percentage
          rsync -a --info=progress2 --no-inc-recursive /source/ /dest/
          echo ""
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "✓ Copy completed successfully!"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "Source size:"
          du -sh /source
          echo "Destination size:"
          du -sh /dest
        volumeMounts:
        - name: source
          mountPath: /source
          readOnly: true
        - name: dest
          mountPath: /dest
      volumes:
      - name: source
        persistentVolumeClaim:
          claimName: $PVC_NAME
      - name: dest
        persistentVolumeClaim:
          claimName: $TEMP_PVC
EOF

echo "  ✓ Copy job created: $JOB_NAME"
echo ""

# Wait for job completion
echo "[7/9] Waiting for copy job to complete..."
echo "  (This may take several minutes depending on data size)"
echo ""

# Smart monitoring function
monitor_copy_job() {
    local job_name=$1
    local namespace=$2
    local timeout_seconds=86400  # 24 hours max total time
    local stall_timeout=300      # 5 minutes of no log activity
    
    local start_time=$(date +%s)
    local last_log_change=$(date +%s)
    local last_log_content=""
    
    echo "  Monitor initialized at $(date)"
    echo "  Max duration: 24h | Stall timeout: 5m"
    echo ""
    
    while true; do
        current_time=$(date +%s)
        elapsed=$((current_time - start_time))
        
        # Check Job Status (Protected against SSH failure)
        JOB_STATUS=$(k get job $job_name -n $namespace -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        JOB_FAILED=$(k get job $job_name -n $namespace -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
        
        # Check success via K8s Status
        if [ "$JOB_STATUS" = "True" ]; then
            echo ""
            echo "  ✓ Copy job completed successfully! (Status Verified)"
            return 0
        fi
        
        # Check Log Activity (Heartbeat) - Fetch more lines for content check
        CURRENT_LOG_BLOCK=$(k logs job/$job_name -n $namespace --tail=50 2>/dev/null || echo "")
        
        if echo "$CURRENT_LOG_BLOCK" | grep -q "Copy completed successfully"; then
             echo ""
             echo "  ✓ Copy job completed successfully! (Log Verified)"
             echo "  --------------------------------------------------"
             echo "$CURRENT_LOG_BLOCK" | grep -v "Copy completed successfully" | tail -n 10
             echo "  --------------------------------------------------"
             return 0
        fi

        if [ "$JOB_FAILED" = "True" ]; then
            echo ""
            echo "  ✗ ERROR: Copy job failed!"
            k logs job/$job_name -n $namespace || true
            return 1
        fi
        
        # Check Total Timeout
        if [ $elapsed -ge $timeout_seconds ]; then
             echo ""
             echo "  ✗ ERROR: Copy job exceeded global timeout of 24h"
             return 1
        fi

        # Extract last line for finding progress
        CURRENT_LOG=$(echo "$CURRENT_LOG_BLOCK" | tail -1)
        
        if [ "$CURRENT_LOG" != "$last_log_content" ]; then
            last_log_change=$current_time
            last_log_content="$CURRENT_LOG"
            # Print update
            echo "  Progressing: $CURRENT_LOG"
        else
            stall_time=$((current_time - last_log_change))
            if [ $stall_time -ge $stall_timeout ]; then
                echo ""
                echo "  ✗ ERROR: Copy job stalled! No log output for $stall_time seconds."
                echo "  Last output: $last_log_content"
                return 1
            fi
            
            # Print keepalive every 30s
            if [ $((elapsed % 30)) -eq 0 ]; then
                 echo "  Still copying... (Time: ${elapsed}s | Last update: ${stall_time}s ago)"
            fi
        fi
        
        sleep 5
    done
}

monitor_copy_job "$JOB_NAME" "$NAMESPACE"
if [ $? -ne 0 ]; then
    echo "  ✗ Copy job monitoring failed"
    exit 1
fi
echo ""

# CRITICAL: Delete job immediately to release volume locks
echo "Cleaning up copy job to release volumes..."
k delete job $JOB_NAME -n $NAMESPACE 2>/dev/null || true
# Wait a moment for pod to disappear
sleep 5
echo "  ✓ Job cleaned up"
echo ""

# Swap PVCs (improved method)
echo "[8/9] Swapping volumes..."

# CRITICAL: Remove finalizers from old PVC BEFORE deletion (prevents Terminating stuck)
echo "  Removing finalizers from old PVC..."
k patch pvc $PVC_NAME -n $NAMESPACE -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

echo "  Deleting old PVC: $PVC_NAME"
k delete pvc $PVC_NAME -n $NAMESPACE --force --grace-period=0 --wait=false 2>/dev/null || true

# Wait a bit for deletion
sleep 3

# Verify old PVC is gone
for i in {1..10}; do
    if ! k get pvc $PVC_NAME -n $NAMESPACE 2>/dev/null | grep -q "$PVC_NAME"; then
        echo "  ✓ Old PVC deleted"
        DELETED_OLD="true"
        break
    fi
    echo "  Waiting for old PVC deletion... ($i/10)"
    sleep 2
done

# CRITICAL: If old PVC still exists, we cannot proceed
if [ "$DELETED_OLD" != "true" ]; then
    echo "  ✗ ERROR: Old PVC failed to delete (stuck in Terminating?)"
    echo "  Attempting finalizer removal again..."
    k patch pvc $PVC_NAME -n $NAMESPACE -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge 2>/dev/null || true
    sleep 2
    if k get pvc $PVC_NAME -n $NAMESPACE 2>/dev/null | grep -q "$PVC_NAME"; then
        echo "  ✗ Aborting: Old PVC still exists. Manual intervention required."
        exit 1
    fi
fi

echo "  Creating new PVC with original name..."

# Get the PV name from temp PVC before we lose it
TEMP_PV_NAME=$(k get pvc $TEMP_PVC -n $NAMESPACE -o jsonpath='{.spec.volumeName}')

# First, patch the PV to change its reclaim policy to Retain (prevent deletion)
# Refactored: Use shared valid function (Protected call)
if ! protect_pv "$NAMESPACE" "$TEMP_PVC"; then
    echo "  ✗ CRITICAL ERROR: Failed to set PV policy to Retain!"
    exit 1
fi

# NOTE: We do NOT patch claimRef here anymore. 
# We must wait for PV to be Released, THEN patch it.

# CRITICAL: Remove finalizers from temp PVC BEFORE deletion (prevents Terminating stuck)
echo "  Removing finalizers from temp PVC..."
k patch pvc $TEMP_PVC -n $NAMESPACE -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true

# Delete temp PVC (should delete quickly now)
echo "  Deleting temporary PVC..."
k delete pvc $TEMP_PVC -n $NAMESPACE --force --grace-period=0 --wait=false 2>/dev/null || true

# Wait for temp PVC to be fully deleted
echo "  Waiting for temp PVC deletion to complete..."
for i in {1..10}; do
    if ! k get pvc $TEMP_PVC -n $NAMESPACE >/dev/null 2>&1; then
        echo "  ✓ Temp PVC deleted"
        break
    fi
    echo "  Temp PVC still exists... ($i/10)"
    sleep 1
done

# Wait for PV to become Available or Released
echo "  Waiting for PV to become Available/Released..."
for i in {1..20}; do
    PV_STATUS=$(k get pv $TEMP_PV_NAME -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    
    # Accept both Available and Released (Longhorn uses Released)
    if [ "$PV_STATUS" = "Released" ]; then
        echo "  ✓ PV is Released"
        break
    fi
    
    if [ "$PV_STATUS" = "Available" ]; then
        echo "  ✓ PV is Available"
        break
    fi
    
    if [ "$PV_STATUS" = "NotFound" ]; then
        echo "  ✗ ERROR: PV not found!"
        exit 1
    fi
    
    echo "  PV status: $PV_STATUS ($i/20)"
    sleep 1
done

# CRITICAL: Now that PV is Released, we MUST clear the claimRef so it becomes Available
# The controller adds the claimRef back upon deletion, so we clear it now.
echo "  Cleaning up claimRef to make PV Available..."
if ! OUTPUT=$(k patch pv $TEMP_PV_NAME -p '{\"spec\":{\"claimRef\":null}}' 2>&1); then
    echo "  ✗ CRITICAL ERROR: Failed to clear claimRef on PV $TEMP_PV_NAME"
    echo "    Error: $OUTPUT"
    echo "    The PV is Retained but not Available. Manual 'kubectl edit pv' required."
    exit 1
fi
sleep 2

# Verify it is Available
PV_STATUS=$(k get pv $TEMP_PV_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
echo "  PV Status after patch: $PV_STATUS"

# Create new PVC with original name, binding to the existing PV
cat <<EOF | k apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
spec:
  accessModes:
    - $ACCESS_MODE
  storageClassName: $STORAGE_CLASS
  volumeName: $TEMP_PV_NAME
  resources:
    requests:
      storage: $NEW_SIZE
EOF

# Wait for new PVC to bind
echo "  Waiting for new PVC to bind..."
for i in {1..30}; do
    NEW_STATUS=$(k get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [ "$NEW_STATUS" = "Bound" ]; then
        echo "  ✓ New PVC bound successfully"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
done

if [ "$NEW_STATUS" != "Bound" ]; then
    echo "  ✗ CRITICAL ERROR: New PVC failed to bind after 30 seconds!"
    echo "  We will NOT restore the PV reclaim policy to Delete."
    echo "  The PV is still set to Retain, so your data is safe."
    echo "  Please check why the PVC is not binding (maybe PV is stuck in Released?)."
    echo "  Manual intervention required."
    exit 1
fi

# Change PV reclaim policy back to Delete
restore_pv_policy "$TEMP_PV_NAME"

echo "  ✓ PVCs swapped successfully"
echo ""

# Scale deployment back up
echo "[9/9] Scaling deployment back to 1..."
k scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=1 2>/dev/null || \
k scale statefulset $DEPLOYMENT -n $NAMESPACE --replicas=1
echo "  ✓ Deployment scaled back to 1"
echo ""

# Cleanup job
echo "Cleaning up copy job..."
k delete job $JOB_NAME -n $NAMESPACE 2>/dev/null || true
echo "  ✓ Job cleaned up"
echo ""

header "✓ SHRINK COMPLETED SUCCESSFULLY!"
echo "Old Size: $CURRENT_SIZE"
echo "New Size: $NEW_SIZE"
echo ""
echo "Verifying pod status..."
sleep 5
k get pod -n $NAMESPACE | grep -E "NAME|$DEPLOYMENT" || true
echo ""
echo "Verifying PVC status..."
k get pvc $PVC_NAME -n $NAMESPACE
echo ""
echo "✓ All done! Volume successfully shrunk."
