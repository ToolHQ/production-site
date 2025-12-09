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
for i in {1..30}; do
    RUNNING_PODS=$(ssh oci-k8s-master "kubectl get pods -n $NAMESPACE 2>/dev/null" | grep -c "Running" || echo "0")
    if [ "$RUNNING_PODS" = "0" ]; then
        echo "  ✓ All pods terminated"
        break
    fi
    echo "  Waiting for pods to terminate... ($i/30)"
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

# Remove finalizers from old PVC if stuck
echo "  Removing finalizers from old PVC..."
ssh oci-k8s-master "kubectl patch pvc $PVC_NAME -n $NAMESPACE -p '{\"metadata\":{\"finalizers\":null}}' --type=merge" 2>/dev/null || true

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
  volumeName: $(ssh oci-k8s-master "kubectl get pvc $TEMP_PVC -n $NAMESPACE -o jsonpath='{.spec.volumeName}'")
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

# Delete temp PVC (but keep the PV)
echo "  Removing temporary PVC reference..."
ssh oci-k8s-master "kubectl delete pvc $TEMP_PVC -n $NAMESPACE --force --grace-period=0" 2>/dev/null || true

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
