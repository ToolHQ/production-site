#!/bin/bash
# async_updater.sh
# Background process to fetch usage metrics and update fzf list
# Usage: ./async_updater.sh <initial_list_file> <display_file> <fzf_port>

INITIAL_LIST=$1
DISPLAY_FILE=$2
FZF_PORT=$3
# Accept explicit cache dir to ensure TUI and Updater share the same path
EXPLICIT_CACHE_DIR=$4
FETCHER_SCRIPT="$(dirname "$0")/fetch_usage_item.sh"

if [ ! -f "$INITIAL_LIST" ] || [ ! -x "$FETCHER_SCRIPT" ]; then
    exit 1
fi

if [ -n "$EXPLICIT_CACHE_DIR" ]; then
    CACHE_DIR="$EXPLICIT_CACHE_DIR"
else
    CACHE_DIR="/tmp/vol_usage_cache_$$"
fi
export CACHE_DIR
mkdir -p "$CACHE_DIR"

# Cleanup on exit (Do NOT delete CACHE_DIR here, parent owns it)
trap 'kill $(jobs -p) 2>/dev/null' EXIT

# --- WATCHER/RENDERER ---
# Function to rebuild display and notify fzf
regenerate_display() {
    > "$DISPLAY_FILE.tmp"
    
    # Add Header Row (Must match fzf --header-lines=1)
    printf "%-20s %-45s %10s %10s %10s\n" "NAMESPACE" "PVC NAME" "ALLOCATED" "USED" "USAGE" >> "$DISPLAY_FILE.tmp"

    # ⚠️ Detect Orphans and Prepend Option (Persistent)
    ORPHAN_COUNT=$(grep -c "Lost" "$INITIAL_LIST" || true)
    if [ "$ORPHAN_COUNT" -gt 0 ]; then
             # Create a special top line (Use distinct formatting)
             SPECIAL_LINE=$(printf "%-20s %-45s %10s %10s %10s" "ALL" "⚠️  CLEAN UP ORPHANS ($ORPHAN_COUNT)" "" "" "")
             echo "$SPECIAL_LINE" >> "$DISPLAY_FILE.tmp"
    fi
    
    # Read initial list and overlay cache
    while IFS= read -r line; do
        # Format: NS|PVC|ALLOC
        NS=$(echo "$line" | cut -d'|' -f1)
        PVC=$(echo "$line" | cut -d'|' -f2)
        ALLOC=$(echo "$line" | cut -d'|' -f3)
        
        CACHE_FILE="$CACHE_DIR/${NS}_${PVC}"
        
        if [ -f "$CACHE_FILE" ]; then
            # Read first two fields for display, ignore the rest (which are for preview cache)
            # CACHE Format: USED|USAGE|POD|CONTAINER|MOUNT|CLASS
            IFS='|' read -r USED USAGE REST < "$CACHE_FILE"
        else
            USED="⏳"
            USAGE="⏳"
        fi
        
        # Consistent Formatting (Wide columns)
        printf "%-20s %-45s %10s %10s %10s\n" "$NS" "$PVC" "$ALLOC" "$USED" "$USAGE" >> "$DISPLAY_FILE.tmp"
    done < "$INITIAL_LIST"
    
    mv "$DISPLAY_FILE.tmp" "$DISPLAY_FILE"
    
    # Trigger Reload
    if [ -n "$FZF_PORT" ]; then
        curl -s -X POST "http://localhost:${FZF_PORT}/reload" >/dev/null 2>&1
    fi
}

# Start Watcher Loop in background
(
    while true; do
        regenerate_display
        sleep 2
    done
) &
WATCHER_PID=$!

# --- WORKERS ---
# Process items in parallel (batch size 10)
export FETCHER_SCRIPT CACHE_DIR

process_item() {
    local line="$1"
    local ns=$(echo "$line" | cut -d'|' -f1)
    local pvc=$(echo "$line" | cut -d'|' -f2)
    
    # Fetch
    local metrics=$("$FETCHER_SCRIPT" "$ns" "$pvc")
    
    # Atomic write pattern: Write to .tmp then move
    local tmp_file="$CACHE_DIR/${ns}_${pvc}.tmp"
    local final_file="$CACHE_DIR/${ns}_${pvc}"
    
    echo "$metrics" > "$tmp_file"
    mv "$tmp_file" "$final_file"
}
export -f process_item

# Use xargs for simple parallelism if available, otherwise loop
# Reduced parallelism to 3 to prevent SSH storm lagging the TUI
cat "$INITIAL_LIST" | xargs -n 1 -P 3 -I {} bash -c 'process_item "$@"' _ {}

# Once all workers done:
kill $WATCHER_PID
regenerate_display # Final update
exit 0
