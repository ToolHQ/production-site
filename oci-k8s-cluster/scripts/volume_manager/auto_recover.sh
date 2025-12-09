#!/bin/bash
# Auto-recovery for volumes showing N/A status
# This happens when pod is not running but PVC exists

set -e

NAMESPACE=$1
PVC_NAME=$2
DEPLOYMENT=$3

if [ -z "$NAMESPACE" ] || [ -z "$PVC_NAME" ] || [ -z "$DEPLOYMENT" ]; then
    echo "Usage: $0 <namespace> <pvc-name> <deployment>"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "AUTO-RECOVERY - Volume N/A Status Fix"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Namespace:   $NAMESPACE"
echo "PVC:         $PVC_NAME"
echo "Deployment:  $DEPLOYMENT"
echo ""

# Check if PVC exists
echo "[1/4] Checking PVC status..."
PVC_STATUS=$(ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.status.phase}'" 2>/dev/null || echo "NotFound")

if [ "$PVC_STATUS" = "NotFound" ]; then
    echo "  ✗ ERROR: PVC not found!"
    exit 1
fi

echo "  PVC Status: $PVC_STATUS"
echo "  PVC Size:   $(ssh oci-k8s-master "kubectl get pvc $PVC_NAME -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}'")"
echo ""

# Check deployment/statefulset status
echo "[2/4] Checking deployment status..."
REPLICAS=$(ssh oci-k8s-master "kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.replicas}'" 2>/dev/null || \
           ssh oci-k8s-master "kubectl get statefulset $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.replicas}'" 2>/dev/null || echo "0")

echo "  Current replicas: $REPLICAS"

if [ "$REPLICAS" = "0" ]; then
    echo "  ⚠️  Deployment is scaled to 0 - this causes N/A status"
    echo ""
    
    # Scale up
    echo "[3/4] Scaling deployment to 1..."
    ssh oci-k8s-master "kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=1" 2>/dev/null || \
    ssh oci-k8s-master "kubectl scale statefulset $DEPLOYMENT -n $NAMESPACE --replicas=1"
    echo "  ✓ Scaled to 1"
    echo ""
    
    # Wait for pod
    echo "[4/4] Waiting for pod to start..."
    for i in {1..30}; do
        POD_STATUS=$(ssh oci-k8s-master "kubectl get pods -n $NAMESPACE 2>/dev/null" | grep "^$DEPLOYMENT" | awk '{print $3}' | head -1)
        if [ "$POD_STATUS" = "Running" ]; then
            echo "  ✓ Pod is Running"
            break
        fi
        echo "  Pod status: $POD_STATUS ($i/30)"
        sleep 2
    done
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✓ RECOVERY COMPLETE!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Volume should now show usage data."
    echo "Refresh the Volume Manager to see updated status."
else
    echo "  ℹ️  Deployment is already running"
    echo ""
    echo "  Possible causes of N/A status:"
    echo "  1. Pod is still starting (wait a few seconds)"
    echo "  2. Volume is not mounted in pod"
    echo "  3. Pod is in error state"
    echo ""
    echo "  Check pod status:"
    ssh oci-k8s-master "kubectl get pods -n $NAMESPACE | grep $DEPLOYMENT"
fi
