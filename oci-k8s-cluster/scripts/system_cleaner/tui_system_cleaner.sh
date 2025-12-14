#!/bin/bash
# tui_system_cleaner.sh
# TUI wrapper for System Cleaner (Log Vacuum / Package Autoremove)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common.sh"
source "$SCRIPT_DIR/../../lib/i18n.sh"


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
        # Node Selection
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
            return 0
        fi

        # Confirmation
        if [ "$SELECTED_NODE" == "ALL" ]; then
            if ! whiptail --title "Confirm Batch Cleaning" --yesno "Are you sure you want to clean SYSTEM LOGS and PACKAGES on ALL nodes?\n\nThis will:\n- Vacuum journals > 2 days\n- Clean apt cache\n- Autoremove unused packages" 12 78; then
                continue
            fi
            
            for node in "${NODES[@]}"; do
                "$SCRIPT_DIR/run_system_cleaner.sh" "$node"
            done
            
            whiptail --title "Success" --msgbox "System Cleanup initiated on ALL nodes." 8 50
        else
            # Single Node
            if ! whiptail --title "Confirm Cleaning" --yesno "Clean $SELECTED_NODE?\n\n- Vacuum journals > 2 days\n- Clean apt cache\n- Autoremove unused packages" 12 60; then
                continue
            fi
            
            clear
            "$SCRIPT_DIR/run_system_cleaner.sh" "$SELECTED_NODE"
            
            echo ""
            echo "Press ENTER to continue..."
            read -r
        fi
    done
}

