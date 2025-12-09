# Volume Manager Functions for k8s_ops_menu.sh
# Part of T-017: TUI Volume Manager
# Add these functions to k8s_ops_menu.sh

# Set whiptail colors to remove pink background
export NEWT_COLORS='root=,black'

# Main volume manager interface
manage_volumes() {
    while true; do
        # Get volume list (fast - shows all PVCs instantly)
        local volumes_data=$(bash scripts/volume_manager/list_volumes_fast.sh 2>/dev/null)
        
        if [ -z "$volumes_data" ]; then
            whiptail --title "Volume Manager" --msgbox "No volumes found or error listing volumes." 8 60
            return
        fi
        
        # Format for fzf display (skip header, show only available fields)
        local volume_list=$(echo "$volumes_data" | tail -n +2 | awk -F'|' '{
            printf "%-20s %-40s %10s\n", $1, $2, $3
        }')
        
        # Select volume with enhanced preview showing additional details
        local selected=$(echo "$volume_list" | "$FZF_BIN" \
            --height=80% \
            --layout=reverse \
            --border \
            --prompt="Select Volume > " \
            --header="NAMESPACE            PVC NAME                                 ALLOCATED" \
            --preview='
                NS={1}
                PVC={2}
                ALLOC={3}
                echo "Volume Details:"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "PVC Information:"
                echo "  Namespace:     $NS"
                echo "  PVC Name:      $PVC"
                echo "  Allocated:     $ALLOC"
                
                # Get pod using this PVC
                POD=$(ssh oci-k8s-master "kubectl get pods -n $NS -o json 2>/dev/null" | jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$PVC\") | .metadata.name" 2>/dev/null | head -1)
                
                if [ -n "$POD" ]; then
                    # Get volume name and mount path
                    VOL_NAME=$(ssh oci-k8s-master "kubectl get pod $POD -n $NS -o json 2>/dev/null" | jq -r ".spec.volumes[] | select(.persistentVolumeClaim.claimName == \"$PVC\") | .name" 2>/dev/null)
                    
                    if [ -n "$VOL_NAME" ]; then
                        # Search ALL containers for this volume mount (not just [0])
                        MOUNT_INFO=$(ssh oci-k8s-master "kubectl get pod $POD -n $NS -o json 2>/dev/null" | jq -r ".spec.containers[] | select(.volumeMounts[]?.name == \"$VOL_NAME\") | .name + \"|\" + (.volumeMounts[] | select(.name == \"$VOL_NAME\") | .mountPath)" 2>/dev/null | head -1)
                        
                        if [ -n "$MOUNT_INFO" ]; then
                            CONTAINER_NAME=$(echo "$MOUNT_INFO" | cut -d"|" -f1)
                            MOUNT_PATH=$(echo "$MOUNT_INFO" | cut -d"|" -f2)
                            
                            # Check if this is a hostPath volume
                            STORAGE_CLASS=$(ssh oci-k8s-master "kubectl get pvc $PVC -n $NS -o jsonpath=\"{.spec.storageClassName}\"" 2>/dev/null)
                            
                            if [ "$STORAGE_CLASS" = "manual" ] || [ "$STORAGE_CLASS" = "hostpath" ]; then
                                # For hostPath, use du to get actual directory usage
                                DU_OUT=$(ssh oci-k8s-master "kubectl exec -n $NS $POD -c $CONTAINER_NAME -- du -sh $MOUNT_PATH 2>/dev/null" 2>/dev/null | head -1)
                                
                                if [ -n "$DU_OUT" ]; then
                                    USED=$(echo "$DU_OUT" | awk "{print \$1}")
                                    ALLOCATED=$(ssh oci-k8s-master "kubectl get pvc $PVC -n $NS -o jsonpath=\"{.spec.resources.requests.storage}\"" 2>/dev/null)
                                    
                                    # Normalize units
                                    USED=$(echo "$USED" | sed "s/^\([0-9.]*\)\([KMGT]\)$/\1\2i/")
                                    
                                    echo "  Used:          $USED (hostPath)"
                                    echo "  Allocated:     $ALLOCATED"
                                    echo "  Usage:         N/A (hostPath - no quota)"
                                    echo "  Mount Point:   $MOUNT_PATH"
                                    echo "  Container:     $CONTAINER_NAME"
                                    echo "  Storage Type:  hostPath (local node storage)"
                                else
                                    echo "  Used:          N/A (du failed for hostPath)"
                                    echo "  Available:     N/A"
                                    echo "  Usage:         N/A"
                                fi
                            else
                                # For Longhorn/network storage, use df
                                DF_OUT=$(ssh oci-k8s-master "kubectl exec -n $NS $POD -c $CONTAINER_NAME -- df -h 2>/dev/null" 2>/dev/null | grep " $MOUNT_PATH\$")
                                
                                if [ -n "$DF_OUT" ]; then
                                    USED=$(echo "$DF_OUT" | awk "{print \$3}")
                                    AVAIL=$(echo "$DF_OUT" | awk "{print \$4}")
                                    PCT=$(echo "$DF_OUT" | awk "{print \$5}")
                                    
                                    # Normalize units (G -> Gi, M -> Mi)
                                    USED=$(echo "$USED" | sed "s/^\([0-9.]*\)\([KMGT]\)$/\1\2i/")
                                    AVAIL=$(echo "$AVAIL" | sed "s/^\([0-9.]*\)\([KMGT]\)$/\1\2i/")
                                    
                                    echo "  Used:          $USED"
                                    echo "  Available:     $AVAIL"
                                    echo "  Usage:         $PCT"
                                    echo "  Mount Point:   $MOUNT_PATH"
                                    echo "  Container:     $CONTAINER_NAME"
                                else
                                    echo "  Used:          N/A (df failed for $MOUNT_PATH)"
                                    echo "  Available:     N/A"
                                    echo "  Usage:         N/A"
                                fi
                            fi
                        else
                            echo "  Used:          N/A (mount not found in any container)"
                            echo "  Available:     N/A"
                            echo "  Usage:         N/A"
                        fi
                    else
                        echo "  Used:          N/A (volume name not found)"
                        echo "  Available:     N/A"
                        echo "  Usage:         N/A"
                    fi
                else
                    echo "  Used:          N/A (no pod)"
                    echo "  Available:     N/A"
                    echo "  Usage:         N/A"
                fi
                
                echo ""
                echo "Additional Details:"
                ssh oci-k8s-master "kubectl get pvc $PVC -n $NS -o json 2>/dev/null" | jq -r "
                    \"  Status:        \" + .status.phase,
                    \"  StorageClass:  \" + .spec.storageClassName,
                    \"  Access Mode:   \" + (.spec.accessModes[0] // \"N/A\"),
                    \"  Volume Mode:   \" + (.spec.volumeMode // \"Filesystem\"),
                    \"  PV Name:       \" + (.spec.volumeName // \"N/A\")
                " 2>/dev/null
                echo ""
                echo "Pods using this volume:"
                ssh oci-k8s-master "kubectl get pods -n $NS -o json 2>/dev/null" | jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$PVC\") | \"  • \" + .metadata.name + \" (\" + .status.phase + \")\"" 2>/dev/null || echo "  None"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            ' \
            --preview-window=right:50%) || return
        
        if [ -z "$selected" ]; then
            return
        fi
        
        # Extract volume info from selection
        local namespace=$(echo "$selected" | awk '{print $1}')
        local pvc_name=$(echo "$selected" | awk '{print $2}')
        local allocated=$(echo "$selected" | awk '{print $3}')
        
        # Get real usage data by querying the pod (same logic as preview)
        echo "Fetching usage data..." >&2
        local usage_data=$(get_volume_usage "$namespace" "$pvc_name")
        local used=$(echo "$usage_data" | cut -d'|' -f1)
        local usage_pct=$(echo "$usage_data" | cut -d'|' -f2)
        
        # Show volume actions menu
        volume_actions_menu "$namespace" "$pvc_name" "$allocated" "$used" "$usage_pct"
    done
}

# Get volume usage data (extracted for reuse)
get_volume_usage() {
    local namespace=$1
    local pvc_name=$2
    
    # Find pod using this PVC
    local pod=$(ssh oci-k8s-master "kubectl get pods -n $namespace -o json 2>/dev/null" | \
                jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$pvc_name\") | .metadata.name" 2>/dev/null | head -1)
    
    if [ -z "$pod" ]; then
        echo "N/A|N/A"
        return
    fi
    
    # Get volume name and mount info
    local vol_name=$(ssh oci-k8s-master "kubectl get pod $pod -n $namespace -o json 2>/dev/null" | \
                     jq -r ".spec.volumes[] | select(.persistentVolumeClaim.claimName == \"$pvc_name\") | .name" 2>/dev/null)
    
    if [ -z "$vol_name" ]; then
        echo "N/A|N/A"
        return
    fi
    
    local mount_info=$(ssh oci-k8s-master "kubectl get pod $pod -n $namespace -o json 2>/dev/null" | \
                       jq -r ".spec.containers[] | select(.volumeMounts[]?.name == \"$vol_name\") | .name + \"|\" + (.volumeMounts[] | select(.name == \"$vol_name\") | .mountPath)" 2>/dev/null | head -1)
    
    if [ -z "$mount_info" ]; then
        echo "N/A|N/A"
        return
    fi
    
    local container_name=$(echo "$mount_info" | cut -d"|" -f1)
    local mount_path=$(echo "$mount_info" | cut -d"|" -f2)
    
    # Get usage via df
    local df_out=$(ssh oci-k8s-master "kubectl exec -n $namespace $pod -c $container_name -- df -h 2>/dev/null" 2>/dev/null | grep " $mount_path\$")
    
    if [ -n "$df_out" ]; then
        local used=$(echo "$df_out" | awk '{print $3}' | sed "s/^\([0-9.]*\)\([KMGT]\)$/\1\2i/")
        local pct=$(echo "$df_out" | awk '{print $5}')
        echo "$used|$pct"
    else
        echo "N/A|N/A"
    fi
}

# Volume actions submenu
volume_actions_menu() {
    local namespace=$1
    local pvc_name=$2
    local allocated=$3
    local used=$4
    local usage_pct=$5
    
    while true; do
        local action=$(whiptail --title "Volume: $namespace/$pvc_name" \
            --menu "Current Size: $allocated | Used: $used ($usage_pct)\n\nChoose action:" 18 70 10 \
            "1" "Expand Volume (increase size)" \
            "2" "Shrink Volume (decrease size - uses snapshot)" \
            "3" "View Details" \
            "4" "Create Snapshot" \
            "5" "Back to Volume List" \
            3>&1 1>&2 2>&3) || return
        
        case $action in
            1)
                resize_volume_expand "$namespace" "$pvc_name" "$allocated"
                ;;
            2)
                resize_volume_shrink "$namespace" "$pvc_name" "$allocated" "$used"
                ;;
            3)
                view_volume_details "$namespace" "$pvc_name"
                ;;
            4)
                create_volume_snapshot "$namespace" "$pvc_name"
                ;;
            5)
                return
                ;;
        esac
    done
}

# Expand volume (native Kubernetes)
resize_volume_expand() {
    local namespace=$1
    local pvc_name=$2
    local current_size=$3
    
    # Get new size from user
    local new_size=$(whiptail --title "Expand Volume" \
        --inputbox "Current size: $current_size\n\nEnter new size (e.g., 10Gi, 500Mi):" 10 60 \
        3>&1 1>&2 2>&3)
    
    if [ -z "$new_size" ]; then
        return
    fi
    
    
    # Confirmation
    if ! whiptail --title "Confirm Expansion" \
        --yesno "Expand $namespace/$pvc_name from $current_size to $new_size?\n\nThis is a safe operation (no data loss)." 10 60; then
        return
    fi
    
    # Clear screen and show progress in real-time
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  EXPAND OPERATION IN PROGRESS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Execute expansion with real-time output
    bash scripts/volume_manager/resize_expand.sh "$namespace" "$pvc_name" "$new_size"
    
    local exit_code=$?
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        echo "✓ EXPAND COMPLETED SUCCESSFULLY"
    else
        echo "✗ EXPAND FAILED"
    fi
    
    echo ""
    read -p "Press ENTER to continue..."
}

# Shrink volume (snapshot-based)
resize_volume_shrink() {
    local namespace=$1
    local pvc_name=$2
    local current_size=$3
    local used=$4
    
    # Warning about shrink
    if ! whiptail --title "⚠️  SHRINK WARNING" \
        --yesno "Shrinking requires:\n\n1. Creating a snapshot\n2. Scaling down workload (DOWNTIME)\n3. Deleting old PVC\n4. Creating new smaller PVC\n5. Restoring from snapshot\n\nEstimated downtime: 2-5 minutes\n\nContinue?" 16 60; then
        return
    fi
    
    # Get new size with clear instructions
    local new_size=$(whiptail --title "Shrink Volume" \
        --inputbox "Current allocated: $current_size\nCurrent usage: $used\n\n⚠️  New size MUST be larger than usage!\n\nEnter new size with unit (e.g., 1Gi, 500Mi, 1.5Gi):\n(Must be > $used)" 14 65 \
        3>&1 1>&2 2>&3)
    
    if [ -z "$new_size" ]; then
        return
    fi
    
    # Get deployment name automatically
    local pod=$(ssh oci-k8s-master "kubectl get pods -n $namespace -o json 2>/dev/null" | \
                jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$pvc_name\") | .metadata.name" 2>/dev/null | head -1)
    
    local deployment=""
    if [ -n "$pod" ]; then
        # Try to get owner (deployment/statefulset)
        deployment=$(ssh oci-k8s-master "kubectl get pod $pod -n $namespace -o json 2>/dev/null" | \
                     jq -r '.metadata.ownerReferences[0].name' 2>/dev/null)
    fi
    
    # Ask for deployment name with auto-detected value as default
    local deployment_input=$(whiptail --title "Deployment Name" \
        --inputbox "Enter deployment/statefulset name:\n\n(Auto-detected from pod using this PVC)" 10 65 \
        "$deployment" \
        3>&1 1>&2 2>&3)
    
    if [ -z "$deployment_input" ]; then
        whiptail --title "Error" --msgbox "Deployment name is required for shrink operation." 8 60 3>&1 1>&2 2>&3
        return
    fi
    
    deployment="$deployment_input"
    
    
    # Final confirmation
    if ! whiptail --title "⚠️  FINAL CONFIRMATION" \
        --yesno "SHRINK OPERATION (Copy-based):\n\nNamespace: $namespace\nPVC: $pvc_name\nDeployment: $deployment\n\nOld Size: $current_size\nNew Size: $new_size\n\nThis will cause DOWNTIME but NO DATA LOSS.\nData will be copied to new volume.\n\nProceed?" 18 65; then
        return
    fi
    
    # Clear screen and show progress in real-time
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  SHRINK OPERATION IN PROGRESS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Watch progress below. This may take several minutes..."
    echo ""
    
    # Execute shrink v2 with real-time output (no capture)
    bash scripts/volume_manager/resize_shrink_v2.sh "$namespace" "$pvc_name" "$new_size" "$deployment"
    
    local exit_code=$?
    
    echo ""
    if [ $exit_code -eq 0 ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  ✓ SHRINK COMPLETED SUCCESSFULLY"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  ✗ SHRINK FAILED"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    fi
    
    echo ""
    read -p "Press ENTER to continue..."
}

# View volume details
view_volume_details() {
    local namespace=$1
    local pvc_name=$2
    
    local details=$(ssh oci-k8s-master "kubectl describe pvc $pvc_name -n $namespace" 2>&1)
    
    whiptail --title "Volume Details: $namespace/$pvc_name" \
        --scrolltext --msgbox "$details" 24 90 \
        3>&1 1>&2 2>&3
}

# Create snapshot
create_volume_snapshot() {
    local namespace=$1
    local pvc_name=$2
    
    local snapshot_name="${pvc_name}-manual-$(date +%Y%m%d-%H%M%S)"
    
    if ! whiptail --title "Create Snapshot" \
        --yesno "Create snapshot of $namespace/$pvc_name?\n\nSnapshot name: $snapshot_name" 10 60; then
        return
    fi
    
    cat <<EOF | ssh oci-k8s-master "kubectl apply -f -"
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $snapshot_name
  namespace: $namespace
spec:
  volumeSnapshotClassName: longhorn-snapshot-vsc
  source:
    persistentVolumeClaimName: $pvc_name
EOF
    
    whiptail --title "Snapshot Created" --msgbox "Snapshot created: $snapshot_name\n\nView with:\nkubectl get volumesnapshot -n $namespace" 10 60
}
