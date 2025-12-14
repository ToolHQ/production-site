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
        
        # Prepare Async Update
        FZF_PORT=$((62000 + RANDOM % 1000))
        INITIAL_LIST_FILE="/tmp/vol_initial_$$.txt"
        DISPLAY_FILE="/tmp/vol_display_$$.txt"
        
        # Explicit Cache Directory to prevent ambiguity and ensure fzf preview looks in invalid place
        CACHE_DIR="/tmp/vol_usage_cache_$$"
        mkdir -p "$CACHE_DIR"
        
        # Save raw list (skip header)
        echo "$volumes_data" | tail -n +2 > "$INITIAL_LIST_FILE"
        
        # Generate initial display list with Green Loading Icons
        > "$DISPLAY_FILE"
        printf "%-20s %-45s %10s %10s %10s\n" "NAMESPACE" "PVC NAME" "ALLOCATED" "USED" "USAGE" > "$DISPLAY_FILE"
        
        while IFS= read -r line; do
             NS=$(echo "$line" | cut -d'|' -f1)
             PVC=$(echo "$line" | cut -d'|' -f2)
             ALLOC=$(echo "$line" | cut -d'|' -f3)
             printf "%-20s %-45s %10s %10s %10s\n" "$NS" "$PVC" "$ALLOC" "⏳" "⏳" >> "$DISPLAY_FILE"
        done < "$INITIAL_LIST_FILE"
        
        # Start Background Updater (Pass explicit CACHE_DIR as 4th arg)
        bash scripts/volume_manager/async_updater.sh "$INITIAL_LIST_FILE" "$DISPLAY_FILE" "$FZF_PORT" "$CACHE_DIR" >/dev/null 2>&1 &
        UPDATER_PID=$!
        
        # Cleanup trap for local scope
        trap "kill $UPDATER_PID 2>/dev/null; rm -rf $INITIAL_LIST_FILE $DISPLAY_FILE $CACHE_DIR" RETURN
 
         
        # Export CACHE_DIR so fzf preview shell can see it
        export CACHE_DIR
        
        # Select volume using FZF with --listen for async updates
        # initial input is piped from cat DISPLAY_FILE
        local selected=$(cat "$DISPLAY_FILE" | "$FZF_BIN" \
            --listen "$FZF_PORT" \
            --header-lines=1 \
            --height=80% \
            --layout=reverse \
            --border \
            --prompt="Select Volume > " \
            --prompt="Select Volume > " \
            --bind "start:reload(cat $DISPLAY_FILE)" \
            --bind "load:reload(cat $DISPLAY_FILE)" \
            --bind "change:reload(cat $DISPLAY_FILE)" \
            --preview="
                # Pure Cache-Based Preview (Zero Latency)
                # FZF quotes the fields (e.g. {1} becomes 'namespace'), so we must assign to variables
                # to lets bash strip the quotes before building the path.
                NS={1}
                PVC={2}
                ALLOC={3}
                
                # Use variables to construct path (Escaped vars are evaluated by preview shell)
                CACHE_FILE=\"$CACHE_DIR/\${NS}_\${PVC}\"
                
                if [ -r \"\$CACHE_FILE\" ]; then
                     IFS=\"|\" read -r c_used c_usage c_pod c_container c_mount c_class c_all_pods c_access_mode < \"\$CACHE_FILE\"
                     
                     echo \"Volume Details:\"
                     echo \"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\"
                     echo \"PVC Information:\"
                     echo \"  Namespace:     \$NS\"
                     echo \"  PVC Name:      \$PVC\"
                     echo \"  Allocated:     \$ALLOC\"
                     echo \"  Access Mode:   \$c_access_mode\"
                     echo \"\"
                     echo \"Usage Metrics:\"
                     echo \"  Used:          \$c_used\"
                     echo \"  Usage:         \$c_usage\"
                     echo \"\"
                     echo \"Mount Details:\"
                     echo \"  Primary Pod:   \$c_pod\"
                     echo \"  Container:     \$c_container\"
                     echo \"  Mount Point:   \$c_mount\"
                     echo \"  Storage Class: \$c_class\"
                     echo \"\"
                     echo \"Attached Pods:\"
                     echo \"  \$c_all_pods\"
                     echo \"  Status:        (Updated)\"
                     echo \"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\"
                else
                     echo \"Loading details... (⏳)\"
                     echo \"\"
                     echo \"PVC: \$PVC\"
                     echo \"NS:  \$NS\"
                     echo \"\"
                     echo \"(Details will appear automatically)\"
                fi
            " \
            --preview-window=right:50%) || return
        
        if [ -z "$selected" ]; then
            return
        fi
        
        # Extract volume info from selection
        # Extract volume info from selection
        local namespace=$(echo "$selected" | awk '{print $1}')
        local pvc_name=$(echo "$selected" | awk '{print $2}')
        local allocated=$(echo "$selected" | awk '{print $3}')
        local used=$(echo "$selected" | awk '{print $4}')
        local usage_pct=$(echo "$selected" | awk '{print $5}')

        # If data was still loading (Hourglass), fetch it synchronously now
        if [ "$used" == "⏳" ] || [ "$used" == "Loading..." ] || [ -z "$used" ]; then
             echo "Fetching usage data..." >&2
             # Use the standalone script we just created instead of internal func?
             # Actually internal func `get_volume_usage` (lines 189+) duplicates `fetch_usage_item.sh`.
             # We should probably deduplicate later. For now, use the internal one or our script.
             # Let's use internal to minimize dependencies inside this block, or use script for consistency.
             # The internal `get_volume_usage` exists in the file.
             local usage_data=$(get_volume_usage "$namespace" "$pvc_name")
             used=$(echo "$usage_data" | cut -d'|' -f1)
             usage_pct=$(echo "$usage_data" | cut -d'|' -f2)
        fi
        
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
        # Build menu options
        local menu_options=(
            "1" "View Details"
            "2" "Expand Volume"
            "3" "Shrink Volume"
            "4" "Create Snapshot"
            "5" "Auto-Recover (N/A fix)"
            "6" "Back"
            "7" "Manage Backup Policies (Auto-Snapshot) 🛡️"
        )
        
        local choice=$(whiptail --title "Volume Actions: $pvc_name" \
            --menu "Namespace: $namespace\nAllocated: $allocated\n\nChoose an action:" 18 70 6 \
            "${menu_options[@]}" \
            3>&1 1>&2 2>&3)
        
        case $choice in
            1) view_volume_details "$namespace" "$pvc_name" "$allocated" ;;
            2) resize_volume_expand "$namespace" "$pvc_name" "$allocated" ;;
            3) resize_volume_shrink "$namespace" "$pvc_name" "$allocated" "$used" ;;
            4) create_volume_snapshot "$namespace" "$pvc_name" ;;
            5) auto_recover_volume "$namespace" "$pvc_name" ;; 
            6) return ;;
            7) manage_backup_policy ;;
            "") return ;;
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
    
    # Calculate safe size (Used / 0.6 = leaves 40% buffer)
    # Extract number and unit
    local used_val=$(echo "$used" | sed 's/[^0-9.]*//g')
    local used_unit=$(echo "$used" | sed 's/[0-9.]*//g')
    local safe_size=""
    local safe_msg=""
    
    if [ -n "$used_val" ]; then
        # Simple calculation using awk
        safe_size=$(awk -v u="$used_val" 'BEGIN {printf "%.0f", u / 0.6 + 1}')
        safe_size="${safe_size}${used_unit}"
        safe_msg="\n\n💡 RECOMMENDED: ${safe_size} (leaves 40% buffer)"
    fi

    # Get new size with clear instructions and safe recommendation
    local new_size=$(whiptail --title "Shrink Volume" \
        --inputbox "Current allocated: $current_size\nCurrent usage: $used${safe_msg}\n\n⚠️  New size MUST be larger than usage!\n\nEnter new size with unit (e.g., 1Gi, 500Mi, 1.5Gi):\n(Must be > $used)" 16 65 \
        "$safe_size" \
        3>&1 1>&2 2>&3)
    
    if [ -z "$new_size" ]; then
        return
    fi
    
    # Get deployment name automatically
    local pod=$(ssh oci-k8s-master "kubectl get pods -n $namespace -o json 2>/dev/null" | \
                jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$pvc_name\") | .metadata.name" 2>/dev/null | head -1)
    
    local deployment=""
    if [ -n "$pod" ]; then
        # Get immediate owner kind and name
        local owner_json=$(ssh oci-k8s-master "kubectl get pod $pod -n $namespace -o json 2>/dev/null")
        local owner_kind=$(echo "$owner_json" | jq -r '.metadata.ownerReferences[0].kind')
        local owner_name=$(echo "$owner_json" | jq -r '.metadata.ownerReferences[0].name')
        
        if [ "$owner_kind" = "ReplicaSet" ]; then
            # Get ReplicaSet's owner (Deployment)
            deployment=$(ssh oci-k8s-master "kubectl get replicaset $owner_name -n $namespace -o jsonpath='{.metadata.ownerReferences[0].name}'" 2>/dev/null)
        else
            deployment="$owner_name"
        fi
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
# Auto-recover volume (fix N/A status)
auto_recover_volume() {
    local namespace=$1
    local pvc_name=$2
    
    # Try to find deployment/statefulset that uses this PVC
    local deployment=""
    
    # Method 1: Check running/recent pods
    deployment=$(ssh oci-k8s-master "kubectl get pods -n $namespace -o json 2>/dev/null" | \
                jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$pvc_name\") | .metadata.ownerReferences[]? | select(.kind == \"StatefulSet\" or .kind == \"ReplicaSet\") | .name" 2>/dev/null | \
                sed 's/-[a-z0-9]\{9,10\}$//' | head -1)
    
    # Method 2: For StatefulSets, check volumeClaimTemplates
    if [ -z "$deployment" ]; then
        deployment=$(ssh oci-k8s-master "kubectl get statefulset -n $namespace -o json 2>/dev/null" | \
                    jq -r ".items[] | select(.spec.volumeClaimTemplates[]?.metadata.name as \$tpl | \"$pvc_name\" | startswith(\$tpl)) | .metadata.name" 2>/dev/null | head -1)
    fi
    
    # Method 3: Try common naming patterns (last resort)
    if [ -z "$deployment" ]; then
        # Remove common PVC suffixes like -0, -1, -pvc, -vol, etc.
        deployment=$(echo "$pvc_name" | sed -E 's/-(pvc|vol|data|storage)-.*$//' | sed 's/-[0-9]*$//')
    fi
    
    if [ -z "$deployment" ]; then
        whiptail --title "Error" --msgbox "Could not auto-detect deployment/statefulset name.\\n\\nPlease scale it manually using kubectl." 10 60 3>&1 1>&2 2>&3
        return
    fi
    
    # Confirmation
    if ! whiptail --title "Auto-Recover Volume" \
        --yesno "This will scale the deployment back to 1 replica to fix N/A status.\\n\\nNamespace: $namespace\\nPVC: $pvc_name\\nDeployment: $deployment\\n\\nProceed?" 14 65; then
        return
    fi
    
    # Clear screen and show progress
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  AUTO-RECOVERY IN PROGRESS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Execute auto-recovery
    bash scripts/volume_manager/auto_recover.sh "$namespace" "$pvc_name" "$deployment"
    
    echo ""
    read -p "Press ENTER to continue..."
}

# Manage Backup Policy
manage_backup_policy() {
    if ! whiptail --title "Backup Policy Manager (Gold Standard)" \
        --yesno "Apply 'Gold Standard' Policy to ALL volumes?\n\n1. Snapshots: Every 1h (Keep 5)\n2. Backups: Daily @ 03:00 (Keep 7)\n\nThis creates Longhorn RecurringJobs and binds all volumes to them." 14 70; then
        return
    fi
    
    clear
    bash scripts/volume_manager/apply_policy.sh
    echo ""
    read -p "Press ENTER to continue..."
}
