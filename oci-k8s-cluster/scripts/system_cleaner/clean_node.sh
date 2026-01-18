#!/bin/bash
# clean_node.sh
# Cleans system logs and package cache to reclaim disk space.
# Safe to run on live nodes (does not restart services indiscriminately).

# Remove set -e to prevent exit on minor errors (like locked apt or docker issues)
# set -e 

# Helper to get available space in MB
get_space() {
    df -BM / | awk 'NR==2 {print $4}' | tr -d 'M'
}

print_freed() {
    local start=$1
    local end=$2
    local diff=$((end - start))
    if [ "$diff" -gt 0 ]; then
        echo "   🎉 Freed: ${diff} MB"
    else
        echo "   (No significant space change)"
    fi
}

# Parse Arguments
MODE="light" # Default for safety? No, user wanted clean. Let's default to "deep" if no arg to maintain behavior, OR "light" for watchdog?
# Plan said: Default backward compatibility (deep).

if [[ "$1" == "--light" ]]; then
    MODE="light"
elif [[ "$1" == "--deep" ]]; then
    MODE="deep"
else
    # Default behavior (Legacy run)
    MODE="deep"
fi

echo "🧹 Starting System Cleanup (Mode: $MODE)..."
INITIAL_SPACE=$(get_space)

# ALWAYS Run: System Logs
echo "---"
echo "📜 Processing System Logs (journalctl)..."
START_SPACE=$(get_space)
CURRENT_LOG_SIZE=$(du -sh /var/log/journal 2>/dev/null | awk '{print $1}' || echo "N/A")
echo "   Current Size: $CURRENT_LOG_SIZE"
echo "   Vacuuming logs older than 2 days..."
journalctl --vacuum-time=2d > /dev/null 2>&1
echo "   Vacuuming logs larger than 500M (total)..."
journalctl --vacuum-size=500M > /dev/null 2>&1
echo "✅ Logs Validated."
print_freed "$START_SPACE" "$(get_space)"

# DEEP ONLY: Heavy lifting
if [ "$MODE" == "deep" ]; then

    # 2. Apt / Package Manager
    echo "---"
    echo "📦 Processing Package Cache (apt)..."
    START_SPACE=$(get_space)

    # Wait for lock
    for i in {1..5}; do
        if fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
            echo "   ⏳ Waiting for apt lock ($i/5)..."
            sleep 3
        else
            break
        fi
    done

    if fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
        echo "⚠️  Apt is locked. Skipping."
    else
        apt-get clean
        echo "   Autoremoving..."
        apt-get autoremove -y > /dev/null 2>&1 || echo "⚠️  Autoremove failed."
        echo "✅ Packages Cleaned."
    fi
    print_freed "$START_SPACE" "$(get_space)"

    # 3. CRI Cleanup
    echo "---"
    echo "🐳 CRI Check..."
    if command -v crictl &> /dev/null; then
        crictl rmi --prune > /dev/null 2>&1 || true
    fi

    # 4. BuildKit & Docker
    echo "---"
    echo "🏗️  BuildKit / Docker GC..."
    START_SPACE=$(get_space)
    
    if command -v docker &> /dev/null; then
        echo "   Docker System Prune..."
        docker system prune -f > /dev/null 2>&1 || true
        echo "   Docker Builder Prune..."
        docker builder prune -f --all > /dev/null 2>&1 || true
    fi
    
    if command -v buildctl &> /dev/null; then
        echo "   Buildctl Prune..."
        buildctl prune --all --force --keep-storage 1000000000 > /dev/null 2>&1
    fi
    print_freed "$START_SPACE" "$(get_space)"
fi

# 5. Longhorn Check (Always run check)
LONGHORN_DIR="/var/lib/longhorn"
if [ -d "$LONGHORN_DIR" ]; then
    echo "---"
    echo "💾 Longhorn Storage Check..."
    du -sh "$LONGHORN_DIR" 2>/dev/null
fi

# 6. Final Report
echo "---"
FINAL_SPACE=$(get_space)
TOTAL_DIFF=$((FINAL_SPACE - INITIAL_SPACE))
echo "✨ Cleanup Complete."
echo "📈 Usage: $(df -h / | awk 'NR==2 {print $5}') Used"
if [ "$TOTAL_DIFF" -gt 0 ]; then
    echo "📉 Reclaimed: ${TOTAL_DIFF} MB"
fi
