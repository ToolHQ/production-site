#!/bin/bash
# Clean Orphaned PVCs
# Filters for PVCs with status 'Lost' and offers deletion.

# Source shared utilities if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/vm_utils.sh" 2>/dev/null || true

# Set whiptail colors
export NEWT_COLORS='root=,black'

cleanup_orphans() {
    # 1. Detect Orphans (Status = Lost)
    # Using list_volumes_fast.sh logic or direct kubectl
    # We use direct kubectl for safety and freshness
    
    ORPHANS=$(ssh oci-k8s-master "kubectl get pvc -A --no-headers" 2>/dev/null | grep "Lost")
    
    if [ -z "$ORPHANS" ]; then
        whiptail --title "Clean Orphans" --msgbox "No orphaned PVCs (Status: Lost) found." 8 60
        return
    fi
    
    # 2. Format list for display
    # Namespace | Name | Capacity | Status
    LIST_TEXT=""
    while read -r line; do
        NS=$(echo "$line" | awk '{print $1}')
        NAME=$(echo "$line" | awk '{print $2}')
        STATUS=$(echo "$line" | awk '{print $3}') # Status is usually 3rd if no capacity, or search for Lost
        # Actually standard output: NS NAME STATUS VOLUME CAPACITY ...
        # If Lost, it might be: NS NAME Lost ...
        
        # We know detection worked, let's just format the line cleanly
        LIST_TEXT="${LIST_TEXT}${line}\n"
    done <<< "$ORPHANS"
    
    # 3. Confirmation Dialog
    if ! whiptail --title "⚠️  CLEAN UP ORPHANS" \
        --yesno "Found the following orphaned PVCs (Status: Lost):\n\n${LIST_TEXT}\n\nThese claims have lost their physical volumes.\nDelete them to clean up the list?" 20 78; then
        return
    fi
    
    # 4. Execute Deletion
    clear
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  CLEANING ORPHANS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    while read -r line; do
        NS=$(echo "$line" | awk '{print $1}')
        NAME=$(echo "$line" | awk '{print $2}')
        
        echo -n "Deleting $NS/$NAME... "
        if ssh oci-k8s-master "kubectl delete pvc $NAME -n $NS --wait=false" 2>/dev/null; then
             echo "✓ Deleted"
             # Patch finalizers just in case it gets stuck
             ssh oci-k8s-master "kubectl patch pvc $NAME -n $NS -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge" >/dev/null 2>&1
        else
             echo "✗ Failed"
        fi
    done <<< "$ORPHANS"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✓ CLEANUP COMPLETED"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    read -p "Press ENTER to continue..."
}

# Run function
cleanup_orphans
