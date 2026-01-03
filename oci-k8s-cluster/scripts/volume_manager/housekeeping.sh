#!/bin/bash
# housekeeping.sh
# Analyzes cluster for stuck/residual volume operations and helps fix them.
# v3.1: Fixes parsing bugs + Adds Pending PVC detection.

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm_utils.sh"

resurrect_pvc() {
    local ns=$1
    local pvc=$2
    
    log "Attempting to Resurrect (Re-establish) $pvc..."
    
    # 1. Get PV Info
    local pv_name=$(k get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.volumeName}' 2>/dev/null)
    local sc=$(k get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
    local size=$(k get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null)
    local mode=$(k get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null)
    
    if [ -z "$pv_name" ]; then
        log "✗ Error: No PV found for $pvc. Cannot resurrect data."
        return 1
    fi
    
    # 2. Protect PV (Using shared util)
    protect_pv "$ns" "$pvc"
    
    # 3. Force Delete Old PVC
    log "Force deleting stuck PVC object..."
    k patch pvc "$pvc" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    k delete pvc "$pvc" -n "$ns" --force --grace-period=0 --wait=false 2>/dev/null || true
    
    # Wait for deletion
    log "Waiting for deletion..."
    for i in {1..10}; do
        if ! k get pvc "$pvc" -n "$ns" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    # 4. Clear PV ClaimRef (Make it Available)
    log "Releasing PV lock (clearing claimRef)..."
    k patch pv "$pv_name" -p '{"spec":{"claimRef":null}}' >/dev/null 2>&1
    sleep 2
    
    # 5. Recreate PVC
    log "Re-creating PVC binding to $pv_name..."
    cat <<EOF | k apply -f - >/dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $pvc
  namespace: $ns
spec:
  accessModes:
    - $mode
  storageClassName: $sc
  volumeName: $pv_name
  resources:
    requests:
      storage: $size
EOF
    
    # 6. Verify Bind
    sleep 3
    local status=$(k get pvc "$pvc" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$status" == "Bound" ]; then
        log "✓ PVC Resurrected and Bound!"
        
        # 7. Restore PV Policy
        restore_pv_policy "$pv_name"
    else
        log "⚠️  Warning: New PVC status is $status (expected Bound)."
    fi
}

header "VOLUME MANAGER HOUSEKEEPING v3.1"
echo "Analyzing cluster state..."
echo ""

# Store findings
declare -a STUCK_JOBS
declare -a TEMP_PVCS
declare -a RESTORED_PVCS
declare -a UNUSED_PVCS
declare -a TERMINATING_PVCS_ORIG
declare -a PENDING_PVCS
declare -a SCALED_DOWN_APPS

# 1. Scan for Stuck Copy Jobs
while read -r ns name rest; do
    if [ -n "$name" ]; then
        STUCK_JOBS+=("$ns|$name")
    fi
done < <(k get jobs -A --no-headers 2>/dev/null | grep "volume-copy-")

# 2. Scan for Temp PVCs
while read -r ns name rest; do
    if [ -n "$name" ]; then
        TEMP_PVCS+=("$ns|$name")
    fi
done < <(k get pvc -A --no-headers 2>/dev/null | grep "\-temp-")

# 3. Scan for "Restored" Leftovers (unused)
while read -r ns name rest; do
    if [ -n "$name" ]; then
        IN_USE=$(k get pods -n "$ns" -o json 2>/dev/null | jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$name\") | .metadata.name")
        if [ -z "$IN_USE" ]; then
             RESTORED_PVCS+=("$ns|$name")
        fi
    fi
done < <(k get pvc -A --no-headers 2>/dev/null | grep "\-restored")

# 4. Scan for Unused/Detached PVCs
while read -r ns name rest; do
    if [ -n "$name" ]; then
        MOUNTED=$(k get pods -n "$ns" -o json 2>/dev/null | jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$name\") | .metadata.name")
        
        if [ -z "$MOUNTED" ]; then
            # Owner Heuristics
            OWNER=""
            BASE_STS=$(echo "$name" | sed 's/-[0-9]*$//')
            if k get statefulset "$BASE_STS" -n "$ns" >/dev/null 2>&1; then
                OWNER="$BASE_STS (StatefulSet)"
            fi
            
            if [ -z "$OWNER" ]; then
                TRY_NAME=$(echo "$name" | sed 's/^logstash-data-//' | sed 's/-[0-9]*$//')
                if k get statefulset "$TRY_NAME" -n "$ns" >/dev/null 2>&1; then
                     OWNER="$TRY_NAME (StatefulSet)"
                fi
            fi
            
            if [ -z "$OWNER" ]; then
                 CLEAN_NAME=$(echo "$name" | sed -E 's/-(pvc|vol|data|storage)-.*$//' | sed 's/-[0-9]*$//')
                 if k get deployment "$CLEAN_NAME" -n "$ns" >/dev/null 2>&1; then
                     OWNER="$CLEAN_NAME (Deployment)"
                 elif k get statefulset "$CLEAN_NAME" -n "$ns" >/dev/null 2>&1; then
                     OWNER="$CLEAN_NAME (StatefulSet)"
                 fi
            fi
            
            if [ -n "$OWNER" ]; then
                 UNUSED_PVCS+=("$ns|$name|$OWNER")
            elif [ "$name" == "logstash-data-oci-logstash-ls-0" ] || [ "$name" == "dlq-vol-oci-logstash-ls-0" ]; then
                 UNUSED_PVCS+=("$ns|$name|oci-logstash-ls (Inferred)")
            fi
        fi
    fi
done < <(k get pvc -A --no-headers 2>/dev/null | grep "Bound" | grep -v "\-temp-" | grep -v "\-restored")

# 5. Scan for Stuck Terminating
while read -r ns name rest; do
    if [ -n "$name" ]; then
        IS_TEMP=0
        if [[ "$name" == *"-temp-"* ]]; then
             IS_TEMP=1
        fi
        
        if [ $IS_TEMP -eq 0 ]; then
             TERMINATING_PVCS_ORIG+=("$ns|$name")
        fi
    fi
done < <(k get pvc -A --no-headers 2>/dev/null | grep "Terminating")

# 6. Scan for Pending PVCs (New)
while read -r ns name rest; do
    if [ -n "$name" ]; then
        PENDING_PVCS+=("$ns|$name")
    fi
done < <(k get pvc -A --no-headers 2>/dev/null | grep "Pending")

# 7. Scan for Scaled Down Apps (New)
# Find running deployments/statefulsets with 0 replicas that have Bound PVCs
while read -r ns name kind; do
    if [ -n "$name" ]; then
        SCALED_DOWN_APPS+=("$ns|$kind|$name")
    fi
done < <(k get statefulset,deployment -A -o json 2>/dev/null | jq -r '.items[] | select(.spec.replicas == 0) | "\(.metadata.namespace) \(.metadata.name) \(.kind)"')


# REPORT AND FIX
# =========================================================

# FIX 1: Stuck Jobs
if [ ${#STUCK_JOBS[@]} -gt 0 ]; then
    echo "⚠️  Found ${#STUCK_JOBS[@]} Stuck Copy Jobs:"
    for item in "${STUCK_JOBS[@]}"; do
        IFS='|' read -r ns name <<< "$item"
        echo "   • $ns / $name"
    done
    
    echo ""
    read -p "Delete these stuck jobs? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for item in "${STUCK_JOBS[@]}"; do
            IFS='|' read -r ns name <<< "$item"
            log "Deleting $name..."
            k delete job "$name" -n "$ns" --force --grace-period=0 2>/dev/null || true
        done
        log "✓ Jobs deleted."
    fi
    echo "--------------------------------------------------------"
fi

# FIX 2: Stuck Terminating ORIGINAL PVCs
if [ ${#TERMINATING_PVCS_ORIG[@]} -gt 0 ]; then
    echo "🚨 Found ${#TERMINATING_PVCS_ORIG[@]} ORIGINAL PVCs stuck in Terminating (Data Risk!):"
    for item in "${TERMINATING_PVCS_ORIG[@]}"; do
        IFS='|' read -r ns name <<< "$item"
        echo "   • $ns / $name"
    done
    
    echo ""
    echo "Options: (r) Resurrect (Re-create & Bind), (d) Force Delete, (s) Skip"
    read -p "Your choice: " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Rr]$ ]]; then
        for item in "${TERMINATING_PVCS_ORIG[@]}"; do
            IFS='|' read -r ns name <<< "$item"
            resurrect_pvc "$ns" "$name"
        done
    elif [[ $REPLY =~ ^[Dd]$ ]]; then
         for item in "${TERMINATING_PVCS_ORIG[@]}"; do
            IFS='|' read -r ns name <<< "$item"
            log "Force Deleting $name (PV Protected)..."
            protect_pv "$ns" "$name"
            k patch pvc "$name" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            k delete pvc "$name" -n "$ns" --force --grace-period=0 --wait=false 2>/dev/null || true
         done
    fi
     echo "--------------------------------------------------------"
fi

# FIX 3: Temp PVCs
if [ ${#TEMP_PVCS[@]} -gt 0 ]; then
    echo "⚠️  Found ${#TEMP_PVCS[@]} Residual Temporary PVCs:"
    for item in "${TEMP_PVCS[@]}"; do
        IFS='|' read -r ns name <<< "$item"
        echo "   • $ns / $name"
    done
    
    echo ""
    echo "Options: (d) Delete Only, (s) Snapshot & Delete, (n) Skip"
    read -p "Your choice: " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        for item in "${TEMP_PVCS[@]}"; do
            IFS='|' read -r ns name <<< "$item"
            snapshot_pvc "$ns" "$name"
            # Delete logic
             protect_pv "$ns" "$name"
             k patch pvc "$name" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
             k delete pvc "$name" -n "$ns" --force --grace-period=0 --wait=false 2>/dev/null || true
        done
        log "✓ Temp PVCs snapshotted and deleted."
    elif [[ $REPLY =~ ^[Dd]$ ]]; then
        for item in "${TEMP_PVCS[@]}"; do
            IFS='|' read -r ns name <<< "$item"
            protect_pv "$ns" "$name"
            k patch pvc "$name" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            k delete pvc "$name" -n "$ns" --force --grace-period=0 --wait=false 2>/dev/null || true
        done
        log "✓ Temp PVCs deleted."
    fi
    echo "--------------------------------------------------------"
fi

# FIX 4: Unused Restored
if [ ${#RESTORED_PVCS[@]} -gt 0 ]; then
    echo "ℹ️  Found ${#RESTORED_PVCS[@]} Unused 'Restored' PVCs:"
    for item in "${RESTORED_PVCS[@]}"; do
        IFS='|' read -r ns name <<< "$item"
        echo "   • $ns / $name"
    done
    
    echo ""
    echo "Options: (d) Delete Only, (s) Snapshot & Delete, (n) Skip"
    read -p "Your choice: " -n 1 -r
    echo ""
     if [[ $REPLY =~ ^[Ss]$ ]]; then
        for item in "${RESTORED_PVCS[@]}"; do
            IFS='|' read -r ns name <<< "$item"
            snapshot_pvc "$ns" "$name"
            k delete pvc "$name" -n "$ns" 2>/dev/null || true
        done
    elif [[ $REPLY =~ ^[Dd]$ ]]; then
        for item in "${RESTORED_PVCS[@]}"; do
            IFS='|' read -r ns name <<< "$item"
             k delete pvc "$name" -n "$ns" 2>/dev/null || true
        done
    fi
     echo "--------------------------------------------------------"
fi

# FIX 5: Unused Valid PVCs
if [ ${#UNUSED_PVCS[@]} -gt 0 ]; then
    echo "🚨 Found ${#UNUSED_PVCS[@]} Valid PVCs with NO pods (Service Downtime?):"
    for item in "${UNUSED_PVCS[@]}"; do
        IFS='|' read -r ns name owner <<< "$item"
        echo "   • $ns / $name (Owner: $owner)"
    done
    
    echo ""
    echo "Options: (r) Recover/Scale-Up Owner, (s) Snapshot Only, (n) Skip"
    read -p "Your choice: " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Rr]$ ]]; then
        for item in "${UNUSED_PVCS[@]}"; do
            IFS='|' read -r ns name owner <<< "$item"
            target=$(echo "$owner" | awk '{print $1}')
            
            log "Scaling up $target in $ns..."
            k scale deployment "$target" -n "$ns" --replicas=1 2>/dev/null || \
            k scale statefulset "$target" -n "$ns" --replicas=1 2>/dev/null || \
            log "warning: Could not scale $target"
        done
        log "✓ Scale up commands issued."
    elif [[ $REPLY =~ ^[Ss]$ ]]; then
        for item in "${UNUSED_PVCS[@]}"; do
            IFS='|' read -r ns name owner <<< "$item"
            snapshot_pvc "$ns" "$name"
        done
    fi
     echo "--------------------------------------------------------"
fi

# FIX 6: Pending PVCs
if [ ${#PENDING_PVCS[@]} -gt 0 ]; then
    echo "🚨 Found ${#PENDING_PVCS[@]} Pending PVCs (Not Bound!):"
    for item in "${PENDING_PVCS[@]}"; do
        IFS='|' read -r ns name <<< "$item"
        echo "   • $ns / $name"
    done
    echo ""
    echo "💡 To fix these, use the 'Auto-Recover (N/A)' option in the Volume Manager menu."
    echo "--------------------------------------------------------"
fi

# FIX 7: Scaled Down Apps (Auto-Recover)
if [ ${#SCALED_DOWN_APPS[@]} -gt 0 ]; then
    echo "⚠️  Found ${#SCALED_DOWN_APPS[@]} Scaled Down Applications (0 Replicas):"
    for item in "${SCALED_DOWN_APPS[@]}"; do
        IFS='|' read -r ns kind name <<< "$item"
        echo "   • $kind: $ns / $name"
    done
    
    echo ""
    read -p "Scale these applications back up to 1 replica? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for item in "${SCALED_DOWN_APPS[@]}"; do
            IFS='|' read -r ns kind name <<< "$item"
            log "Scaling up $kind $name in $ns..."
            if [ "$kind" == "StatefulSet" ]; then
                k scale statefulset "$name" -n "$ns" --replicas=1 2>/dev/null || true
            else
                k scale deployment "$name" -n "$ns" --replicas=1 2>/dev/null || true
            fi
        done
        log "✓ Applications scaled up."
    fi
    echo "--------------------------------------------------------"
fi

# FIX 8: Longhorn Orphaned Data
LH_IP=$(k -n longhorn-system get svc longhorn-frontend -o jsonpath="{.spec.clusterIP}" 2>/dev/null)
if [ -n "$LH_IP" ]; then
    ORPHANS_JSON=$(curl -s "http://$LH_IP/v1/orphans")
    ORPHAN_COUNT=$(echo "$ORPHANS_JSON" | jq -r ".data[].id" 2>/dev/null | wc -w)
    
    if [ "$ORPHAN_COUNT" -gt 0 ]; then
        echo "🧹 Found $ORPHAN_COUNT Longhorn Orphaned Data entries (Zombie replicas)."
        echo ""
        read -p "Clean up these orphans? (y/N) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            IDS=$(echo "$ORPHANS_JSON" | jq -r ".data[].id")
            for id in $IDS; do
                log "Deleting orphan $id..."
                curl -s -X DELETE "http://$LH_IP/v1/orphans/$id" >/dev/null
            done
            log "✓ Orphans cleaned."
        fi
        echo "--------------------------------------------------------"
    fi
fi

echo ""
echo "Housekeeping Complete."
read -p "Press ENTER to continue..."
