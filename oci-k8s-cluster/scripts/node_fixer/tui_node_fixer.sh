#!/bin/bash
# tui_node_fixer.sh
# TUI Module for Longhorn Node Fixer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common.sh"
source "$SCRIPT_DIR/../../scripts/volume_manager/vm_utils.sh"

FIXER_DIR="$SCRIPT_DIR"

run_cluster_doctor() {
    echo -e "${YELLOW}🚑 Running Cluster Doctor...${NC}"
    echo "Scanning for unhealthy pods (CrashLoopBackOff, ImagePullBackOff, Error, Unknown)..."
    
    # Capture unhealthy pods
    # Format: NAMESPACE POD STATUS
    local unhealthy_pods
    unhealthy_pods=$(run_kubectl "get pods -A --no-headers" | grep -E 'CrashLoopBackOff|ImagePullBackOff|ErrImagePull|Error|Unknown|Evicted' | awk '{print $1, $2, $4}' || true)
    
    if [ -z "$unhealthy_pods" ]; then
        whiptail --title "Cluster Doctor" --msgbox "✅ Great news! No unhealthy pods found." 8 50
        return
    fi
    
    # Display list
    local pod_list_formatted=$(echo "$unhealthy_pods" | column -t)
    echo -e "\n${RED}Found Unhealthy Pods:${NC}\n$pod_list_formatted\n"
    
    if whiptail --title "Cluster Doctor" --yesno "Found $(echo "$unhealthy_pods" | wc -l) unhealthy pods.\n\nDo you want to DELETE them to force a restart?\n(This often fixes stuck pods or token issues)" 15 80; then
        echo -e "${YELLOW}💉 Applying Fixes...${NC}"
        
        while read -r line; do
            local ns=$(echo "$line" | awk '{print $1}')
            local pod=$(echo "$line" | awk '{print $2}')
            echo "   -> Deleting $pod in $ns..."
            run_kubectl "delete pod -n $ns $pod --grace-period=0 --force" >/dev/null 2>&1
        done <<< "$unhealthy_pods"
        
        echo -e "${GREEN}✅ All targets neutralized. Kubernetes will restart them automatically.${NC}"
        echo "Wait 30s and check status again."
        read -p "Press ENTER to continue..."
    else
        echo "Cancelled."
    fi
}

node_fixer_menu() {
    while true; do
        # 1. Select Node
        local node_options=()
        
        # Add "Doctor" as the first special option
        node_options+=("DOCTOR" "🚑 Run Cluster Doctor (Fix Stuck Pods)")
        
        local i=0
        for n in "${NODES[@]}"; do
            local role="Worker"
            if [ $i -eq 0 ]; then
                role="Master"
            fi
            
            # Fetch IP locally via ssh config (fast)
            local ip
            ip=$(ssh -G "$n" | grep -i "^hostname " | awk '{print $2}')
            
            # Format: (Role) - IP
            node_options+=("$n" "($role) - $ip")
            i=$((i+1))
        done
        
        # Add "ALL NODES" option
        node_options+=("ALL" " Apply to ALL Nodes")
        
        local selected_node
        selected_node=$(whiptail --title "Node Fixer & Doctor" \
            --menu "Select Target:" 18 70 8 \
            "${node_options[@]}" \
            3>&1 1>&2 2>&3) || selected_node=""
            
        if [ -z "$selected_node" ]; then
            return
        fi
        
        if [ "$selected_node" == "DOCTOR" ]; then
            clear
            run_cluster_doctor
            continue
        fi
        
        if [ "$selected_node" == "ALL" ]; then
             if whiptail --title "Confirm Batch Fix" --yesno "Apply fixes to ALL nodes?\nThis will restart multipathd service on all nodes." 10 60; then
                for n in "${NODES[@]}"; do
                    "$FIXER_DIR/run_node_fixer.sh" "$n"
                done
                whiptail --msgbox "All nodes processed!" 8 40
             fi
        else
            if whiptail --title "Confirm Fix" --yesno "Apply fixes to $selected_node?" 10 60; then
                clear
                "$FIXER_DIR/run_node_fixer.sh" "$selected_node"
                echo "Press ENTER to continue..."
                read -r
            fi
        fi
    done
}
