#!/bin/bash
# tui_node_fixer.sh
# TUI Module for Longhorn Node Fixer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common.sh"
source "$SCRIPT_DIR/../../scripts/volume_manager/vm_utils.sh"

FIXER_DIR="$SCRIPT_DIR"

node_fixer_menu() {
    while true; do
        # 1. Select Node
        local node_options=()
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
        selected_node=$(whiptail --title "Longhorn Prerequisites Fixer" \
            --menu "Select a node to apply fixes (dm_crypt, multipathd):" 15 60 6 \
            "${node_options[@]}" \
            3>&1 1>&2 2>&3) || selected_node=""
            
        if [ -z "$selected_node" ]; then
            return
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
