#!/bin/bash
# tui_disk.sh
# TUI Module for Node Disk Optimization (Image Management)

# Ensure common vars
DISK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Relies on common.sh being sourced by the parent script usually, but sourcing here doesn't hurt.
source "$DISK_DIR/../../common.sh"
source "$DISK_DIR/../../scripts/volume_manager/vm_utils.sh"

DISK_MGR_DIR="$DISK_DIR/../../scripts/disk_manager"

node_disk_optimizer_menu() {
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
        
        local selected_node
        selected_node=$(whiptail --title "Node Disk Optimizer" \
            --menu "Select a node to inspect images:" 15 60 5 \
            "${node_options[@]}" \
            3>&1 1>&2 2>&3) || selected_node=""
            
        if [ -z "$selected_node" ]; then
            return
        fi
        
        # 2. Manage Images Loop
        image_manager_loop "$selected_node"
    done
}

image_manager_loop() {
    local node=$1
    
    while true; do
        # Fetch Images
        echo "⏳ Fetching images from $node..."
        local image_list_file="/tmp/k8s_ops_images_$$"
        "$DISK_MGR_DIR/list_images.sh" "$node" > "$image_list_file"
        
        if [ ! -s "$image_list_file" ]; then
            whiptail --msgbox "No images found on $node or connection failed." 10 50
            rm -f "$image_list_file"
            return
        fi
        
        # FZF Interface
        # Format: "VisualPart \t FullID"
        # --delimiter=$'\t' splits by tab
        # --with-nth=1 shows only VisualPart
        
        # Sort State File
        local sort_file="/tmp/k8s_ops_sort_$$.txt"
        echo "size" > "$sort_file"

        local selected_lines
        selected_lines=$(cat "$image_list_file" | "$FZF_BIN" \
            --multi \
            --delimiter=$'\t' \
            --with-nth=1 \
            --header="TAB/SPACE: Select | CTRL-A: All | CTRL-S: Toggle Sort (Safe/Size) | ENTER: Delete" \
            --layout=reverse \
            --border \
            --marker="* " \
            --pointer="->" \
            --prompt="Size Sort > " \
            --bind "ctrl-r:reload($DISK_MGR_DIR/list_images.sh $node $sort_file)" \
            --bind "space:toggle+down" \
            --bind "ctrl-a:select-all" \
            --bind "ctrl-d:deselect-all" \
            --bind "ctrl-s:execute-silent(grep -q safe $sort_file && echo size > $sort_file || echo safe > $sort_file)+reload($DISK_MGR_DIR/list_images.sh $node $sort_file)+change-prompt(Safe/Size > )" \
            --expect=ctrl-p \
        ) || true
        
        rm -f "$sort_file"
        
        local fzf_exit=$?
        
        # Read key press (first line of output from --expect)
        local key=$(echo "$selected_lines" | head -1)
        # Remaining lines are the selection
        local selection=$(echo "$selected_lines" | tail -n +2)
        
        rm -f "$image_list_file"

        if [ -z "$selected_lines" ]; then
            # Cancelled
            return
        fi
        
        if [ "$key" == "ctrl-p" ]; then
            # PRUNE ACTION
             if whiptail --title "Confirm Prune" --yesno "Are you sure you want to PRUNE all dangling images on $node?\nThis is usually safe and removes unused layers." 10 60; then
                clear
                "$DISK_MGR_DIR/prune_images.sh" "$node" --prune
                echo "Press ENTER to continue..."
                read -r
             fi
             continue
        fi

        if [ -z "$selection" ]; then
            continue
        fi
        
        # DELETE SELECTED ACTION
        # Extract FullIDs (Part after tab)
        local ids_to_delete=()
        while IFS=$'\t' read -r visual full_id; do
            if [ -n "$full_id" ]; then
                ids_to_delete+=("$full_id")
            fi
        done <<< "$selection"
        
        local count=${#ids_to_delete[@]}
        
        if [ $count -gt 0 ]; then
             if whiptail --title "Confirm Deletion" --yesno "Delete $count selected images from $node?\n\nIf an image is in use, it will NOT be deleted (safe)." 10 60; then
                clear
                # Pass all IDs to prune script
                "$DISK_MGR_DIR/prune_images.sh" "$node" "${ids_to_delete[@]}"
                echo "Press ENTER to continue..."
                read -r
             fi
        fi
        
    done
}
