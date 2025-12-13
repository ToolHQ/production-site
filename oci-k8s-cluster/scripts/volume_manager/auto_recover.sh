#!/bin/bash
# Auto-recovery for volumes showing N/A status or Pending state (v3)
# Updates: Handles Released PVs (Ghost Volumes)
# Refactored: Uses vm_utils.sh

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm_utils.sh"

NAMESPACE=$1
PVC_NAME=$2
DEPLOYMENT=$3

if [ -z "$NAMESPACE" ] || [ -z "$PVC_NAME" ] || [ -z "$DEPLOYMENT" ]; then
    echo "Usage: $0 <namespace> <pvc-name> <deployment>"
    exit 1
fi

header "AUTO-RECOVERY - Volume Status Fix v3"
echo "Namespace:   $NAMESPACE"
echo "PVC:         $PVC_NAME"
echo "Deployment:  $DEPLOYMENT"
echo ""

# 1. Check if PVC exists
echo "[1/4] Checking PVC status..."
PVC_JSON=$(k get pvc "$PVC_NAME" -n "$NAMESPACE" -o json 2>/dev/null || echo "")

if [ -z "$PVC_JSON" ]; then
    log "✗ ERROR: PVC not found!"
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

# 2. Handle Pending State (Lost or Ghost PV)
if [ "$PVC_STATUS" = "Pending" ] && [ -n "$TARGET_PV" ]; then
    echo "[2/4] Analyzing Pending state..."
    # Check PV status
    PV_PHASE=$(k get pv "$TARGET_PV" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    
    echo "  PV Status:  $PV_PHASE"
    
    if [ "$PV_PHASE" = "NotFound" ]; then
        log "⚠️  CRITICAL ISSUE DETECTED: Lost PV"
        echo "  The PVC points to volume '$TARGET_PV' which does not exist."
        echo "  Data is likely lost."
        echo "" 
        
        read -p "  Action: Recreate empty volume to restore service? (y/N): " verify
        if [[ "$verify" =~ ^[Yy]$ ]]; then
            log "Recreating volume..."
            k delete pvc "$PVC_NAME" -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true
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
  resources:
    requests:
      storage: $CAPACITY
EOF
            log "✓ Volume recreated. Waiting for binding..."
            sleep 5
            k delete pod -n "$NAMESPACE" -l app="$DEPLOYMENT" --force --grace-period=0 2>/dev/null || true
            exit 0
        fi
        
    elif [ "$PV_PHASE" = "Released" ]; then
        echo ""
        log "⚠️  ISSUE DETECTED: Ghost Volume (Released)"
        echo "  The PV exists but is 'Released' (locked to old PVC UID)."
        echo "  We can unlock it to restore your data immediately."
        echo ""
        
        read -p "  Action: Unlock PV to restore data? (y/N): " verify
        if [[ "$verify" =~ ^[Yy]$ ]]; then
             log "Unlocking PV..."
             k patch pv "$TARGET_PV" -p '{"spec":{"claimRef":null}}'
             log "✓ PV Unlocked. Waiting for bind..."
             for i in {1..30}; do
                 NEW_STATUS=$(k get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
                 if [ "$NEW_STATUS" = "Bound" ]; then
                     log "✓ PVC Bound successfully!"
                     break
                 fi
                 sleep 1
             done
             echo ""
             log "Restarting pod..."
             # Specific fix for cost-analyzer if needed, but generic deployment restart is below
             k delete pod -n "$NAMESPACE" -l app.kubernetes.io/name=cost-analyzer --force --grace-period=0 2>/dev/null || true
             k delete pod -n "$NAMESPACE" -l app="$DEPLOYMENT" --force --grace-period=0 2>/dev/null || true
             
             header "✓ RECOVERY COMPLETE - DATA RESTORED"
             exit 0
        fi
    fi
fi

# 3. Check deployment/statefulset status (N/A Usage Case)
echo "[3/4] Checking deployment status..."
REPLICAS=$(k get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || \
           k get statefulset "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

echo "  Current replicas: $REPLICAS"

if [ "$REPLICAS" = "0" ]; then
    log "⚠️  Deployment is scaled to 0 - this causes N/A status"
    echo ""
    
    # Scale up
    echo "[4/4] Scaling deployment to 1..."
    k scale deployment "$DEPLOYMENT" -n "$NAMESPACE" --replicas=1 2>/dev/null || \
    k scale statefulset "$DEPLOYMENT" -n "$NAMESPACE" --replicas=1
    log "✓ Scaled to 1"
    echo ""
    
    # Wait for pod
    echo "  Waiting for pod to start..."
    for i in {1..30}; do
        POD_STATUS=$(k get pods -n "$NAMESPACE" 2>/dev/null | grep -E "$DEPLOYMENT|${DEPLOYMENT}-0" | awk '{print $3}' | head -1)
        if [ "$POD_STATUS" = "Running" ]; then
            log "✓ Pod is Running"
            break
        fi
        echo "  Pod status: $POD_STATUS ($i/30)"
        sleep 2
    done
    
    header "✓ RECOVERY COMPLETE"
else
    log "ℹ️  Deployment is already running"
    echo ""
    echo "  Check pod status:"
    k get pods -n "$NAMESPACE" | grep -E "$DEPLOYMENT|${DEPLOYMENT}-0"
fi
