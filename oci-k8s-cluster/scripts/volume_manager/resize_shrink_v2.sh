#!/bin/bash
# Volume Shrink v2 - Copy-based strategy (IMPROVED)
# Safer approach: Create new volume, copy data, swap volumes

set -e

NAMESPACE=$1
PVC_NAME=$2
NEW_SIZE=$3
DEPLOYMENT=$4

if [ -z "$NAMESPACE" ] || [ -z "$PVC_NAME" ] || [ -z "$NEW_SIZE" ] || [ -z "$DEPLOYMENT" ]; then
    echo "Usage: $0 <namespace> <pvc-name> <new-size> <deployment>"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SHRINK VOLUME - Copy-based Strategy v2"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Namespace:   $NAMESPACE"
echo "PVC:         $PVC_NAME"
echo "New Size:    $NEW_SIZE"
echo "Deployment:  $DEPLOYMENT"
echo ""

# Cleanup function for rollback
cleanup_on_error() {
    echo ""
    echo "⚠️  ERROR DETECTED - Attempting cleanup..."
    
    # Scale deployment back up
    echo "  Scaling deployment back to 1..."
    ssh oci-k8s-master "kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=1" 2>/dev/null || \
    ssh oci-k8s-master "kubectl scale statefulset $DEPLOYMENT -n $NAMESPACE --replicas=1" 2>/dev/null || true
    
    # Delete temp PVC if exists
    if [ -n "$TEMP_PVC" ]; then
        echo "  Deleting temporary PVC: $TEMP_PVC"
        ssh oci-k8s-master "kubectl delete pvc $TEMP_PVC -n $NAMESPACE --force --grace-period=0" 2>/dev/null || true
    fi
    
    # Delete job if exists
    if [ -n "$JOB_NAME" ]; then
        echo "  Deleting copy job: $JOB_NAME"
        ssh oci-k8s-master "kubectl delete job $JOB_NAME -n $NAMESPACE" 2>/dev/null || true
    fi
    
    echo "  ✓ Cleanup completed"
    exit 1
}

trap cleanup_on_error ERR

# Get current PVC info
echo "[1/9] Getting current PVC information..."
STORAGE_CLASS=$(ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.storageClassName}'")
ACCESS_MODE=$(ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.accessModes[0]}'")
CURRENT_SIZE=$(ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}'")

echo "  Current Size:    $CURRENT_SIZE"
echo "  Storage Class:   $STORAGE_CLASS"
echo "  Access Mode:     $ACCESS_MODE"
echo ""

# Scale down deployment
echo "[2/9] Scaling down deployment to 0..."
ssh oci-k8s-master "kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=0" 2>/dev/null || \
ssh oci-k8s-master "kubectl scale statefulset $DEPLOYMENT -n $NAMESPACE --replicas=0"
echo "  ✓ Deployment scaled to 0"
echo ""

# Wait for pod termination
echo "[3/9] Waiting for pod termination..."
sleep 5

# Determine if it's a deployment or statefulset and get pod selector
RESOURCE_TYPE=$(ssh oci-k8s-master "kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o name 2>/dev/null" && echo "deployment" || echo "statefulset")

for i in {1..30}; do
    # Check only pods belonging to this specific deployment/statefulset
    if [ "$RESOURCE_TYPE" = "deployment" ]; then
        RUNNING_PODS=$(ssh oci-k8s-master "kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT 2>/dev/null" | grep -c "Running" || echo "0")
    else
        # For statefulset, check by name pattern
        RUNNING_PODS=$(ssh oci-k8s-master "kubectl get pods -n $NAMESPACE 2>/dev/null" | grep "^$DEPLOYMENT-" | grep -c "Running" || echo "0")
    fi
    
    if [ "$RUNNING_PODS" = "0" ]; then
        echo "  ✓ All pods from $DEPLOYMENT terminated"
        break
    fi
    echo "  Waiting for $DEPLOYMENT pods to terminate... ($i/30)"
    sleep 2
done
echo ""

# Create temporary PVC
TEMP_PVC="${PVC_NAME}-temp-$(date +%Y%m%d-%H%M%S)"
echo "[4/9] Creating temporary PVC: $TEMP_PVC"

cat <<EOF | ssh oci-k8s-master "kubectl apply -f -"
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
    STATUS=$(ssh oci-k8s-master "kubectl get pvc $TEMP_PVC -n $NAMESPACE -o jsonpath='{.status.phase}'")
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

cat <<EOF | ssh oci-k8s-master "kubectl apply -f -"
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
          rsync -av --progress /source/ /dest/
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

for i in {1..600}; do
    JOB_STATUS=$(ssh oci-k8s-master "kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Complete\")].status}'" 2>/dev/null || echo "")
    JOB_FAILED=$(ssh oci-k8s-master "kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Failed\")].status}'" 2>/dev/null || echo "")
    
    if [ "$JOB_STATUS" = "True" ]; then
        echo ""
        echo "  ✓ Copy job completed successfully!"
        echo ""
        echo "  Job logs (last 15 lines):"
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        ssh oci-k8s-master "kubectl logs job/$JOB_NAME -n $NAMESPACE" | tail -15 | sed 's/^/  /'
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        break
    fi
    
    if [ "$JOB_FAILED" = "True" ]; then
        echo ""
        echo "  ✗ ERROR: Copy job failed!"
        echo ""
        ssh oci-k8s-master "kubectl logs job/$JOB_NAME -n $NAMESPACE"
        exit 1
    fi
    
    if [ $((i % 10)) -eq 0 ]; then
        echo "  Still copying... ($i/600 seconds)"
    fi
    sleep 1
done

if [ "$JOB_STATUS" != "True" ]; then
    echo "  ✗ ERROR: Copy job timed out after 10 minutes"
    exit 1
fi
echo ""

# Swap PVCs (improved method)
echo "[8/9] Swapping volumes..."

# CRITICAL: Remove finalizers from old PVC BEFORE deletion (prevents Terminating stuck)
echo "  Removing finalizers from old PVC..."
ssh oci-k8s-master "kubectl patch pvc $PVC_NAME -n $NAMESPACE -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge" 2>/dev/null || true

echo "  Deleting old PVC: $PVC_NAME"
ssh oci-k8s-master "kubectl delete pvc $PVC_NAME -n $NAMESPACE --force --grace-period=0 --wait=false" 2>/dev/null || true

# Wait a bit for deletion
sleep 3

# Verify old PVC is gone
for i in {1..10}; do
    if ! ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE" 2>/dev/null | grep -q "$PVC_NAME"; then
        echo "  ✓ Old PVC deleted"
        break
    fi
    echo "  Waiting for old PVC deletion... ($i/10)"
    sleep 2
done

echo "  Creating new PVC with original name..."

# Get the PV name from temp PVC before we lose it
TEMP_PV_NAME=$(ssh oci-k8s-master "kubectl get pvc $TEMP_PVC -n $NAMESPACE -o jsonpath='{.spec.volumeName}'")

# First, patch the PV to change its reclaim policy to Retain (prevent deletion)
echo "  Setting PV reclaim policy to Retain..."
ssh oci-k8s-master "kubectl patch pv $TEMP_PV_NAME -p '{\"spec\":{\"persistentVolumeReclaimPolicy\":\"Retain\"}}'"

# CRITICAL: Remove claimRef from PV BEFORE deleting PVC (prevents hang)
echo "  Releasing PV from temp PVC..."
ssh oci-k8s-master "kubectl patch pv $TEMP_PV_NAME -p '{\"spec\":{\"claimRef\":null}}'"

# CRITICAL: Remove finalizers from temp PVC BEFORE deletion (prevents Terminating stuck)
echo "  Removing finalizers from temp PVC..."
ssh oci-k8s-master "kubectl patch pvc $TEMP_PVC -n $NAMESPACE -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge" 2>/dev/null || true

# Delete temp PVC (should delete quickly now)
echo "  Deleting temporary PVC..."
ssh oci-k8s-master "kubectl delete pvc $TEMP_PVC -n $NAMESPACE --force --grace-period=0" 2>/dev/null || true

# Wait for temp PVC to be fully deleted
echo "  Waiting for temp PVC deletion to complete..."
for i in {1..10}; do
    if ! ssh oci-k8s-master "kubectl get pvc $TEMP_PVC -n $NAMESPACE" >/dev/null 2>&1; then
        echo "  ✓ Temp PVC deleted"
        break
    fi
    echo "  Temp PVC still exists... ($i/10)"
    sleep 1
done

# Wait for PV to become Available or Released
echo "  Waiting for PV to become Available/Released..."
for i in {1..20}; do
    PV_STATUS=$(ssh oci-k8s-master "kubectl get pv $TEMP_PV_NAME -o jsonpath='{.status.phase}'" 2>/dev/null || echo "NotFound")
    
    # Accept both Available and Released (Longhorn uses Released)
    if [ "$PV_STATUS" = "Available" ] || [ "$PV_STATUS" = "Released" ]; then
        echo "  ✓ PV is $PV_STATUS"
        break
    fi
    
    if [ "$PV_STATUS" = "NotFound" ]; then
        echo "  ✗ ERROR: PV not found!"
        exit 1
    fi
    
    if [ $i -eq 20 ]; then
        echo "  ✗ ERROR: PV stuck in $PV_STATUS state after 20 seconds"
        echo "  This might indicate a Longhorn issue. Check PV manually:"
        echo "  kubectl describe pv $TEMP_PV_NAME"
        exit 1
    fi
    
    echo "  PV status: $PV_STATUS ($i/20)"
    sleep 1
done

# Create new PVC with original name, binding to the existing PV
cat <<EOF | ssh oci-k8s-master "kubectl apply -f -"
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
    NEW_STATUS=$(ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.status.phase}'" 2>/dev/null || echo "")
    if [ "$NEW_STATUS" = "Bound" ]; then
        echo "  ✓ New PVC bound successfully"
        break
    fi
    echo "  Waiting... ($i/30)"
    sleep 2
done

# Change PV reclaim policy back to Delete
echo "  Restoring PV reclaim policy to Delete..."
ssh oci-k8s-master "kubectl patch pv $TEMP_PV_NAME -p '{\"spec\":{\"persistentVolumeReclaimPolicy\":\"Delete\"}}'"

echo "  ✓ PVCs swapped successfully"
echo ""

# Scale deployment back up
echo "[9/9] Scaling deployment back to 1..."
ssh oci-k8s-master "kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=1" 2>/dev/null || \
ssh oci-k8s-master "kubectl scale statefulset $DEPLOYMENT -n $NAMESPACE --replicas=1"
echo "  ✓ Deployment scaled back to 1"
echo ""

# Cleanup job
echo "Cleaning up copy job..."
ssh oci-k8s-master "kubectl delete job $JOB_NAME -n $NAMESPACE" 2>/dev/null || true
echo "  ✓ Job cleaned up"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ SHRINK COMPLETED SUCCESSFULLY!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Old Size: $CURRENT_SIZE"
echo "New Size: $NEW_SIZE"
echo ""
echo "Verifying pod status..."
sleep 5
ssh oci-k8s-master "kubectl get pod -n $NAMESPACE | grep -E 'NAME|$DEPLOYMENT'" || true
echo ""
echo "Verifying PVC status..."
ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE"
echo ""
echo "✓ All done! Volume successfully shrunk."
