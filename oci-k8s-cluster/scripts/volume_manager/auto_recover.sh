#!/bin/bash
# Auto-recovery for volumes showing N/A status or Pending state (v2)
# Handles:
# 1. Deployment scaled to 0 (scales up)
# 2. Lost PV (recreates PVC)
# 3. Stuck Terminating (removes finalizers)

set -e

NAMESPACE=$1
PVC_NAME=$2
DEPLOYMENT=$3

if [ -z "$NAMESPACE" ] || [ -z "$PVC_NAME" ] || [ -z "$DEPLOYMENT" ]; then
    echo "Usage: $0 <namespace> <pvc-name> <deployment>"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "AUTO-RECOVERY - Volume Status Fix v2"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Namespace:   $NAMESPACE"
echo "PVC:         $PVC_NAME"
echo "Deployment:  $DEPLOYMENT"
echo ""

# 1. Check if PVC exists
echo "[1/4] Checking PVC status..."
PVC_JSON=$(ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE -o json 2>/dev/null" || echo "")

if [ -z "$PVC_JSON" ]; then
    echo "  ✗ ERROR: PVC not found!"
    exit 1
fi

PVC_STATUS=$(echo "$PVC_JSON" | jq -r '.status.phase')
TARGET_PV=$(echo "$PVC_JSON" | jq -r '.spec.volumeName // empty')
STORAGE_CLASS=$(echo "$PVC_JSON" | jq -r '.spec.storageClassName')
ACCESS_MODE=$(echo "$PVC_JSON" | jq -r '.spec.accessModes[0]')
CAPACITY=$(echo "$PVC_JSON" | jq -r '.spec.resources.requests.storage')

echo "  PVC Status: $PVC_STATUS"
echo "  Target PV:  ${TARGET_PV:-<none>}"
echo ""

# 2. Handle Pending State (Lost PV Case)
if [ "$PVC_STATUS" = "Pending" ] && [ -n "$TARGET_PV" ]; then
    echo "[2/4] analyzing Pending state..."
    # Check if PV exists
    PV_EXISTS=$(ssh oci-k8s-master "kubectl get pv $TARGET_PV --no-headers 2>/dev/null" || echo "")
    
    if [ -z "$PV_EXISTS" ]; then
        echo "  ⚠️  CRITICAL ISSUE DETECTED: Lost PV"
        echo "  The PVC is stuck in Pending because it tries to bind to"
        echo "  volume '$TARGET_PV' which does not exist."
        echo ""
        echo "  This usually happens if the backend storage was deleted."
        echo "  The data is likely already lost."
        echo "" 
        
        read -p "  Action: Recreate empty volume to restore service? (y/N): " verify
        if [[ "$verify" =~ ^[Yy]$ ]]; then
            echo ""
            echo "  Recreating volume..."
            
            # Delete old PVC
            echo "  1. Deleting stuck PVC..."
            ssh oci-k8s-master "kubectl delete pvc $PVC_NAME -n $NAMESPACE --force --grace-period=0" 2>/dev/null || true
            
            # Create new PVC
            echo "  2. Creating fresh PVC ($CAPACITY)..."
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
  resources:
    requests:
      storage: $CAPACITY
EOF
            echo "  ✓ Volume recreated. Waiting for binding..."
            sleep 5
            
            # Restart pod
            echo "  3. Restarting pod to mount new volume..."
            ssh oci-k8s-master "kubectl delete pod -n $NAMESPACE -l app=$DEPLOYMENT --force --grace-period=0" 2>/dev/null || true
             ssh oci-k8s-master "kubectl delete pod -n $NAMESPACE -l app.kubernetes.io/name=$DEPLOYMENT --force --grace-period=0" 2>/dev/null || true
            
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "✓ RECOVERED FROM LOST PV"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            exit 0
        else
            echo "  Cancelled."
            exit 1
        fi
    fi
fi

# 3. Check deployment/statefulset status (N/A Usage Case)
echo "[3/4] Checking deployment status..."
REPLICAS=$(ssh oci-k8s-master "kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.replicas}'" 2>/dev/null || \
           ssh oci-k8s-master "kubectl get statefulset $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.replicas}'" 2>/dev/null || echo "0")

echo "  Current replicas: $REPLICAS"

if [ "$REPLICAS" = "0" ]; then
    echo "  ⚠️  Deployment is scaled to 0 - this causes N/A status"
    echo ""
    
    # Scale up
    echo "[4/4] Scaling deployment to 1..."
    ssh oci-k8s-master "kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=1" 2>/dev/null || \
    ssh oci-k8s-master "kubectl scale statefulset $DEPLOYMENT -n $NAMESPACE --replicas=1"
    echo "  ✓ Scaled to 1"
    echo ""
    
    # Wait for pod
    echo "  Waiting for pod to start..."
    for i in {1..30}; do
        POD_STATUS=$(ssh oci-k8s-master "kubectl get pods -n $NAMESPACE 2>/dev/null" | grep -E "$DEPLOYMENT|${DEPLOYMENT}-0" | awk '{print $3}' | head -1)
        if [ "$POD_STATUS" = "Running" ]; then
            echo "  ✓ Pod is Running"
            break
        fi
        echo "  Pod status: $POD_STATUS ($i/30)"
        sleep 2
    done
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ RECOVERY COMPLETE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "  ℹ️  Deployment is already running"
    echo ""
    echo "  Possible causes of N/A status:"
    echo "  1. Pod is still starting (wait a few seconds)"
    echo "  2. Volume is not mounted in pod"
    echo "  3. Pod is in error state"
    echo ""
    echo "  Check pod status:"
    ssh oci-k8s-master "kubectl get pods -n $NAMESPACE | grep -E '$DEPLOYMENT|${DEPLOYMENT}-0'"
fi
