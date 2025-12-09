# Volume Manager Functions for k8s_ops_menu.sh
# Part of T-017: TUI Volume Manager
# Add these functions to k8s_ops_menu.sh

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
                        MOUNT_PATH=$(ssh oci-k8s-master "kubectl get pod $POD -n $NS -o json 2>/dev/null" | jq -r ".spec.containers[0].volumeMounts[] | select(.name == \"$VOL_NAME\") | .mountPath" 2>/dev/null)
                        
                        if [ -n "$MOUNT_PATH" ]; then
                            # Get df output for the exact mount point
                            DF_OUT=$(ssh oci-k8s-master "kubectl exec -n $NS $POD -- df -h 2>/dev/null" 2>/dev/null | grep " $MOUNT_PATH\$")
                            
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
                            else
                                echo "  Used:          N/A (df failed for $MOUNT_PATH)"
                                echo "  Available:     N/A"
                                echo "  Usage:         N/A"
                            fi
                        else
                            echo "  Used:          N/A (mount path not found for vol: $VOL_NAME)"
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
        
        # Extract volume info
        local namespace=$(echo "$selected" | awk '{print $1}')
        local pvc_name=$(echo "$selected" | awk '{print $2}')
        local allocated=$(echo "$selected" | awk '{print $3}')
        local used=$(echo "$selected" | awk '{print $4}')
        local usage_pct=$(echo "$selected" | awk '{print $5}')
        
        # Show volume actions menu
        volume_actions_menu "$namespace" "$pvc_name" "$allocated" "$used" "$usage_pct"
    done
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
    
    # Execute expansion
    bash scripts/volume_manager/resize_expand.sh "$namespace" "$pvc_name" "$new_size" 2>&1 | \
        whiptail --title "Expanding Volume" --scrolltext --msgbox /dev/stdin 20 80
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
    
    # Get new size
    local new_size=$(whiptail --title "Shrink Volume" \
        --inputbox "Current size: $current_size\nCurrent usage: $used\n\nEnter new size (must be > $used):" 12 60 \
        3>&1 1>&2 2>&3)
    
    if [ -z "$new_size" ]; then
        return
    fi
    
    # Get deployment name
    local deployment=$(whiptail --title "Deployment Name" \
        --inputbox "Enter deployment/statefulset name (e.g., postgres-deployment):" 10 60 \
        3>&1 1>&2 2>&3)
    
    if [ -z "$deployment" ]; then
        whiptail --title "Error" --msgbox "Deployment name is required for shrink operation." 8 60
        return
    fi
    
    # Final confirmation
    if ! whiptail --title "⚠️  FINAL CONFIRMATION" \
        --yesno "SHRINK OPERATION:\n\nNamespace: $namespace\nPVC: $pvc_name\nDeployment: $deployment\n\nOld Size: $current_size\nNew Size: $new_size\n\nThis will cause DOWNTIME but NO DATA LOSS (snapshot-based).\n\nProceed?" 18 60; then
        return
    fi
    
    # Execute shrink
    bash scripts/volume_manager/resize_shrink.sh "$namespace" "$pvc_name" "$new_size" "$deployment" 2>&1 | \
        whiptail --title "Shrinking Volume" --scrolltext --msgbox /dev/stdin 24 90
}

# View volume details
view_volume_details() {
    local namespace=$1
    local pvc_name=$2
    
    local details=$(ssh oci-k8s-master "kubectl describe pvc $pvc_name -n $namespace")
    
    echo "$details" | whiptail --title "Volume Details: $namespace/$pvc_name" \
        --scrolltext --msgbox /dev/stdin 24 90
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
