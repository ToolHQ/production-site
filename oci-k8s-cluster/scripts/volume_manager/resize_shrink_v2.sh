#!/bin/bash
# Volume Shrink v2 - Copy-based strategy
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
echo "SHRINK VOLUME - Copy-based Strategy"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Namespace:   $NAMESPACE"
echo "PVC:         $PVC_NAME"
echo "New Size:    $NEW_SIZE"
echo "Deployment:  $DEPLOYMENT"
echo ""

# Get current PVC info
echo "[1/8] Getting current PVC information..."
STORAGE_CLASS=$(ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.storageClassName}'")
ACCESS_MODE=$(ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.accessModes[0]}'")
CURRENT_SIZE=$(ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}'")

echo "  Current Size:    $CURRENT_SIZE"
echo "  Storage Class:   $STORAGE_CLASS"
echo "  Access Mode:     $ACCESS_MODE"
echo ""

# Scale down deployment
echo "[2/8] Scaling down deployment to 0..."
ssh oci-k8s-master "kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=0" 2>/dev/null || \
ssh oci-k8s-master "kubectl scale statefulset $DEPLOYMENT -n $NAMESPACE --replicas=0"
echo "  ✓ Deployment scaled to 0"
echo ""

# Wait for pod termination
echo "[3/8] Waiting for pod termination..."
sleep 5
while ssh oci-k8s-master "kubectl get pods -n $NAMESPACE -l app=$DEPLOYMENT 2>/dev/null | grep -v NAME | grep -q Running"; do
    echo "  Waiting for pods to terminate..."
    sleep 2
done
echo "  ✓ All pods terminated"
echo ""

# Create temporary PVC
TEMP_PVC="${PVC_NAME}-temp-$(date +%Y%m%d-%H%M%S)"
echo "[4/8] Creating temporary PVC: $TEMP_PVC"

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
echo "[5/8] Waiting for temporary PVC to be bound..."
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
echo "[6/8] Creating data copy job..."
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
          echo "Starting data copy..."
          rsync -av --progress /source/ /dest/
          echo "Copy completed successfully!"
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
echo "[7/8] Waiting for copy job to complete..."
for i in {1..300}; do
    JOB_STATUS=$(ssh oci-k8s-master "kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Complete\")].status}'")
    JOB_FAILED=$(ssh oci-k8s-master "kubectl get job $JOB_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Failed\")].status}'")
    
    if [ "$JOB_STATUS" = "True" ]; then
        echo "  ✓ Copy job completed successfully!"
        echo ""
        echo "  Job logs:"
        ssh oci-k8s-master "kubectl logs job/$JOB_NAME -n $NAMESPACE" | tail -10
        break
    fi
    
    if [ "$JOB_FAILED" = "True" ]; then
        echo "  ✗ ERROR: Copy job failed!"
        ssh oci-k8s-master "kubectl logs job/$JOB_NAME -n $NAMESPACE"
        exit 1
    fi
    
    if [ $((i % 10)) -eq 0 ]; then
        echo "  Still copying... ($i/300 seconds)"
    fi
    sleep 1
done

if [ "$JOB_STATUS" != "True" ]; then
    echo "  ✗ ERROR: Copy job timed out"
    exit 1
fi
echo ""

# Swap PVCs
echo "[8/8] Swapping volumes..."
echo "  Deleting old PVC: $PVC_NAME"
ssh oci-k8s-master "kubectl delete pvc $PVC_NAME -n $NAMESPACE --wait=true"

echo "  Renaming temporary PVC to original name..."
ssh oci-k8s-master "kubectl get pvc $TEMP_PVC -n $NAMESPACE -o yaml" | \
    sed "s/name: $TEMP_PVC/name: $PVC_NAME/" | \
    sed '/uid:/d' | \
    sed '/resourceVersion:/d' | \
    sed '/creationTimestamp:/d' | \
    ssh oci-k8s-master "kubectl apply -f -"

ssh oci-k8s-master "kubectl delete pvc $TEMP_PVC -n $NAMESPACE"
echo "  ✓ PVCs swapped"
echo ""

# Scale deployment back up
echo "Scaling deployment back to 1..."
ssh oci-k8s-master "kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=1" 2>/dev/null || \
ssh oci-k8s-master "kubectl scale statefulset $DEPLOYMENT -n $NAMESPACE --replicas=1"
echo "  ✓ Deployment scaled back to 1"
echo ""

# Cleanup job
echo "Cleaning up copy job..."
ssh oci-k8s-master "kubectl delete job $JOB_NAME -n $NAMESPACE"
echo "  ✓ Job cleaned up"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ SHRINK COMPLETED SUCCESSFULLY!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Old Size: $CURRENT_SIZE"
echo "New Size: $NEW_SIZE"
echo ""
echo "Verify the pod is running:"
echo "  kubectl get pod -n $NAMESPACE"
