#!/bin/bash
# tui_system_cleaner.sh
# TUI wrapper for System Cleaner (Log Vacuum / Package Autoremove)

CLEANER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$CLEANER_DIR/../../common.sh"
source "$CLEANER_DIR/../../lib/i18n.sh"


system_cleaner_menu() {
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

    while true; do
        ACTION=$(whiptail --title "System & Cluster Cleaner" \
            --menu "Select Maintenance Task:" \
            15 60 5 \
            "1" "Clean System Logs/Packages (Nodes)" \
            "2" "Prune Kubernetes Garbage (Jobs/Pods)" \
            "0" "Back" \
            3>&1 1>&2 2>&3) || ACTION=""
            
        if [ -z "$ACTION" ] || [ "$ACTION" == "0" ]; then
            return 0
        fi
        
        if [ "$ACTION" == "2" ]; then
            clear
            "$CLEANER_DIR/prune_k8s_garbage.sh"
            echo ""
            read -p "Press ENTER to continue..."
            continue
        fi

        # Node Selection (For Action 1)
        NODES_LIST=()
        for n in "${NODES[@]}"; do
            NODES_LIST+=("$n" "")
        done
        NODES_LIST+=("ALL" "Run on ALL Nodes (Batch)")

        SELECTED_NODE=$(whiptail --title "System Maintenance Cleaner" \
            --menu "Select a node to clean (Logs/Apt/Kernels):" \
            20 70 10 \
            "${NODES_LIST[@]}" \
            3>&1 1>&2 2>&3) || SELECTED_NODE=""

        if [ -z "$SELECTED_NODE" ]; then
            continue
        fi

        # Confirmation
        if [ "$SELECTED_NODE" == "ALL" ]; then
            if ! whiptail --title "Confirm Batch Cleaning" --yesno "Are you sure you want to clean SYSTEM LOGS and PACKAGES on ALL nodes?\n\nThis will:\n- Vacuum journals > 2 days\n- Clean apt cache\n- Autoremove unused packages" 12 78; then
                continue
            fi
            
            for node in "${NODES[@]}"; do
                "$CLEANER_DIR/run_system_cleaner.sh" "$node"
            done
            
            whiptail --title "Success" --msgbox "System Cleanup initiated on ALL nodes." 8 50
        else
            # Single Node
            if ! whiptail --title "Confirm Cleaning" --yesno "Clean $SELECTED_NODE?\n\n- Vacuum journals > 2 days\n- Clean apt cache\n- Autoremove unused packages" 12 60; then
                continue
            fi
            
            clear
            "$CLEANER_DIR/run_system_cleaner.sh" "$SELECTED_NODE"
            
            echo ""
            echo "Press ENTER to continue..."
            read -r
        fi
    done
}

# Run menu if executed directly
system_cleaner_menu

