#!/bin/bash
# kubecost_view.sh
# Fetches savings opportunities from Kubecost API and displays them in TUI.

FINOPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$FINOPS_DIR/../../common.sh"
source "$FINOPS_DIR/../../lib/i18n.sh"

export NEWT_COLORS='
root=,blue
window=,lightgray
border=black,lightgray
textbox=black,lightgray
button=black,lightgray
compactbutton=black,lightgray
listbox=black,lightgray
actlistbox=black,cyan
actsellistbox=black,cyan
'

KUBECOST_IP="10.96.179.60"
KUBECOST_PORT="9090"
BASE_URL="http://${KUBECOST_IP}:${KUBECOST_PORT}/model"
API_URL="${BASE_URL}/savings?window=7d"

echo "⏳ Fetching FinOps Report from Kubecost..."

# 1. Fetch JSON
# We use 'ssh master' because master has direct access to ClusterIP, 
# although we might have access from here too if we are on the jumpbox within the network.
# Using SSH to master is safer/standardized in this environment.

JSON_DATA=$(ssh oci-k8s-master "curl -s -m 5 '$API_URL'" 2>/dev/null) || JSON_DATA=""

if [ -z "$JSON_DATA" ]; then
    whiptail --title "Error" --msgbox "Could not fetch data from Kubecost ($KUBECOST_IP).\nCheck if service is running." 10 60
    exit 1
fi

# 2. Parse Data using jq
# We extract the 'production' profile items
# Format: KEY|VALUE (value is monthly savings)

PARSED_DATA=$(echo "$JSON_DATA" | jq -r '.production | to_entries[] | "\(.key)|\(.value.value)"')

# 3. Create Display List
DISPLAY_LIST=()
TOTAL_SAVINGS=0

# Helper to map keys to titles
get_title() {
    case "$1" in
        "abandonedWorkload") echo "Abandoned Workloads" ;;
        "clusterSizing") echo "Cluster Right-Sizing" ;;
        "localDisks") echo "Local Disk Cleanup" ;;
        "nodeTurndown") echo "Node Turndown (Scale Down)" ;;
        "orphanedResources") echo "Orphaned Resources" ;;
        "pvSizing") echo "Persistent Volume Sizing" ;;
        "requestSizing") echo "Right-size Requests" ;;
        "reservedInstances") echo "Reserved Instances" ;;
        "spotResources") echo "Spot Instances" ;;
        "unclaimedVolumes") echo "Unclaimed Volumes" ;;
        *) echo "$1" ;;
    esac
}

while IFS='|' read -r key value; do
    # Skip null or empty values
    if [ "$value" == "null" ] || [ -z "$value" ]; then
        val_float=0
    else
        val_float=$(printf "%.2f" "$value")
    fi
    
    # Calculate Total using awk (bc might be missing)
    if [ $(awk "BEGIN {print ($val_float > 0)}") -eq 1 ]; then
        TOTAL_SAVINGS=$(awk "BEGIN {print $TOTAL_SAVINGS + $val_float}")
        
        TITLE=$(get_title "$key")
        # Use Key as TAG, Title+Price as ITEM
        DISPLAY_ITEM="${TITLE} ... ${val_float}/mo"
        
        DISPLAY_LIST+=("$key" "$DISPLAY_ITEM")
    fi
done <<< "$PARSED_DATA"

TOTAL_SAVINGS_FMT=$(printf "%.2f" "$TOTAL_SAVINGS")

if [ ${#DISPLAY_LIST[@]} -eq 0 ]; then
    whiptail --title "FinOps Report" --msgbox "No savings opportunities found! 🎉\nYour cluster is fully optimized." 10 60
    exit 0
fi

# 4. Show Menu
# 4. Show Menu Loop
while true; do
    SELECTED=$(whiptail --title "💰 Kubecost FinOps Report" \
        --menu "Total Potential Savings: US\$ ${TOTAL_SAVINGS_FMT}/mo\n\nSelect a strategy to view details:" \
        20 100 10 \
        "${DISPLAY_LIST[@]}" \
        3>&1 1>&2 2>&3)
    
    EXIT_STATUS=$?
    if [ $EXIT_STATUS -ne 0 ]; then
        exit 0
    fi
    
    # 5. Show Details
    # 5. Show Details
    if [ "$SELECTED" == "requestSizing" ]; then
        echo "⏳ Fetching Rightsizing recommendations..."
        
        # Fetch Data
        REQ_JSON=$(ssh oci-k8s-master "curl -s -m 5 '${BASE_URL}/savings/requestSizing?window=7d'" 2>/dev/null) || REQ_JSON=""
        
        # Parse: SAVINGS | NS | KIND | NAME | CONTAINER | T_CPU | T_RAM
        # We select items with savings > $0.10
        # We prefer the first container if multiple (simplification for MVP)
        PARSED_REQS=$(echo "$REQ_JSON" | jq -r '.controllers[] | select(.monthlySavings > 0.1) | 
            "\(.monthlySavings)|\(.namespace)|\(.type)|\(.name)|\(.containers | keys[0])|\(.containers[].target.cpuCores // 0)|\(.containers[].target.ramBytes // 0)"' | sort -rn)
        
        if [ -z "$PARSED_REQS" ]; then
             whiptail --title "Rightsizing" --msgbox "No significant sizing recommendations found." 8 60
             continue
        fi

        # Build Checklist with Index Mapping
        CHECKLIST_ARGS=()
        DATA_MAP=()
        IDX=1
        
        while IFS='|' read -r savings ns kind name container t_cpu t_ram; do
            if [ -n "$name" ] && [ "$name" != "null" ]; then
                # Format: "NS/Name" "Save $X - Kind: Y" OFF
                s_fmt=$(printf "%.2f" "$savings")
                
                # Store real data in map (0-based array, so use IDX-1 or just IDX)
                # We use string joining for the map value
                DATA_VAL="${ns}:${kind}:${name}:${container}:${t_cpu}:${t_ram}"
                DATA_MAP[$IDX]="$DATA_VAL"
                
                # Display: Name (Container) - $Savings
                DISPLAY="${name} [${container}] - Save \$${s_fmt}/mo"
                
                CHECKLIST_ARGS+=("$IDX" "$DISPLAY" "OFF")
                ((IDX++))
            fi
        done <<< "$PARSED_REQS"
        
        # Show Checklist
        # We use a simple index as the Tag to keep the UI clean
        SELECTIONS=$(whiptail --title "💸 Rightsizing Candidates" \
            --checklist "Select workloads to AUTO-RESIZE based on Kubecost recommendations:\n(Items with 0 target will undergo 'Safe Floor' resizing)" \
            22 100 12 \
            "${CHECKLIST_ARGS[@]}" \
            3>&1 1>&2 2>&3)
            
        if [ $? -eq 0 ] && [ -n "$SELECTIONS" ]; then
            # Process Selections
            # Remove quotes
            SELECTIONS=$(echo "$SELECTIONS" | tr -d '"')
            
            clear
            echo "🚀 Applying optimzations..."
            echo "--------------------------------"
            
            for S_IDX in $SELECTIONS; do
                # Lookup real data from map
                ITEM="${DATA_MAP[$S_IDX]}"
                
                if [ -n "$ITEM" ]; then
                    # Split ID
                    IFS=':' read -r p_ns p_kind p_name p_container p_cpu p_ram <<< "$ITEM"
                    
                    echo "Processing #$S_IDX: $p_kind/$p_name ($p_container)..."
                    # Clean up dirty kind if needed (e.g. null/empty defaults)
                    if [ -z "$p_kind" ] || [ "$p_kind" == "null" ]; then p_kind="deployment"; fi
                    
                    bash "$FINOPS_DIR/apply_resize.sh" "$p_ns" "$p_kind" "$p_name" "$p_container" "$p_cpu" "$p_ram"
                else
                    echo "⚠️  Error: Could not map selection #$S_IDX to data."
                fi
            done
            
            echo "--------------------------------"
            echo "✅ Batch processing complete."
            echo "Press ENTER to return to report..."
            read -r
        fi
        
    elif [ "$SELECTED" == "abandonedWorkload" ]; then
        echo "⏳ Fetching Abandoned Workloads..."
        
        ABD_JSON=$(ssh oci-k8s-master "curl -s -m 5 '${BASE_URL}/savings/abandonedWorkloads?window=7d'" 2>/dev/null) || ABD_JSON=""
        
        # Parse: NS | KIND | NAME
        # Deduplicate by owner
        # SAFETY FILTER: Exclude CRITICAL system namespaces
        PARSED_ABD=$(echo "$ABD_JSON" | jq -r 'group_by(.owners[0].namespace + .owners[0].name) | map(.[0]) | .[] | select(.owners[0].name != null) | select(.namespace | test("kube-system|longhorn-system|cert-manager|monitoring|kubecost|calico-system|tigera-operator|ingress-nginx") | not) | "\(.namespace)|\(.owners[0].kind)|\(.owners[0].name)"')
        
        if [ -z "$PARSED_ABD" ]; then
             whiptail --title "Abandoned Workloads" --msgbox "No (Safe-to-Remove) abandoned workloads detected.\n\n(System components were hidden for safety)" 10 60
             continue
        fi

        # Build Checklist
        CHECKLIST_ARGS=()
        DATA_MAP=()
        IDX=1
        
        while IFS='|' read -r ns kind name; do
             # Store data
             DATA_VAL="${ns}:${kind}:${name}"
             DATA_MAP[$IDX]="$DATA_VAL"
             
             # Display
             DISPLAY="${ns}/${name} ($kind)"
             CHECKLIST_ARGS+=("$IDX" "$DISPLAY" "OFF")
             ((IDX++))
        done <<< "$PARSED_ABD"
        
        SELECTIONS=$(whiptail --title "👻 Abandoned Candidates" \
            --checklist "Select workloads to SUSPEND (Scale to 0):\n(These workloads have little to no traffic)" \
            22 100 12 \
            "${CHECKLIST_ARGS[@]}" \
            3>&1 1>&2 2>&3)
            
        if [ $? -eq 0 ] && [ -n "$SELECTIONS" ]; then
            SELECTIONS=$(echo "$SELECTIONS" | tr -d '"')
            
            # --- SAFETY CHECK: Detect Risky Workloads ---
            RISKY_ITEMS=""
            SAFE_ITEMS=""
            for S_IDX in $SELECTIONS; do
                ITEM="${DATA_MAP[$S_IDX]}"
                if [[ "$ITEM" =~ "postgres" ]] || [[ "$ITEM" =~ "minio" ]] || [[ "$ITEM" =~ "mysql" ]] || [[ "$ITEM" =~ "mongo" ]] || [[ "$ITEM" =~ "redis" ]] || [[ "$ITEM" =~ "db" ]]; then
                    # Extract name for display
                    IFS=':' read -r r_ns r_kind r_name <<< "$ITEM"
                    RISKY_ITEMS+="$r_ns/$r_name\n"
                fi
            done
            
            # --- CONFIRMATION DIALOGS ---
            if [ -n "$RISKY_ITEMS" ]; then
                whiptail --title "⚠️ CRITICAL WARNING" --yesno "You have selected STATEFUL/DATABASE workloads:\n\n$RISKY_ITEMS\nSuspending these will STOP your database/storage.\nAre you absolutely sure?" 12 70
                if [ $? -ne 0 ]; then
                    continue # Cancel and return to list
                fi
            else
                # Standard confirmation for non-risky items
                 whiptail --title "Confirm Suspension" --yesno "You are about to scale ${#SELECTIONS[@]} workloads to 0 replicas.\nThey will stop processing traffic.\n\nProceed?" 10 60
                 if [ $? -ne 0 ]; then
                    continue
                 fi
            fi
            
            clear
            echo "🚀 Suspending workloads..."
            echo "--------------------------------"
            
            for S_IDX in $SELECTIONS; do
                ITEM="${DATA_MAP[$S_IDX]}"
                if [ -n "$ITEM" ]; then
                    IFS=':' read -r p_ns p_kind p_name <<< "$ITEM"
                    echo "Processing #$S_IDX: $p_kind/$p_name..."
                    bash "$FINOPS_DIR/apply_scale_zero.sh" "$p_ns" "$p_kind" "$p_name"
                fi
            done
            echo "--------------------------------"
            echo "✅ Batch processing complete."
            echo "Press ENTER to return to report..."
            read -r
        fi
        
    else
        # Default fallback for other items
        DETAILS=$(echo "$JSON_DATA" | jq -r ".production.\"$SELECTED\"")
        whiptail --title "Details: $SELECTED" --scrolltext --msgbox "$DETAILS" 20 100
    fi
done
