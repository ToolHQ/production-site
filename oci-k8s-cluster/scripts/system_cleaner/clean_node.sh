#!/bin/bash
# clean_node.sh
# Cleans system logs and package cache to reclaim disk space.
# Safe to run on live nodes (does not restart services indiscriminately).

set -e

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

echo "🧹 Starting System Cleanup..."
INITIAL_SPACE=$(get_space)

# 1. Systemd Journal Logs
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

# 2. Apt / Package Manager
echo "---"
echo "📦 Processing Package Cache (apt)..."
START_SPACE=$(get_space)

# Wait for lock (up to 30s)
for i in {1..10}; do
    if fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
        echo "   ⏳ Waiting for apt lock to be released ($i/10)..."
        sleep 3
    else
        break
    fi
done

if fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
    LOCK_PID=$(fuser /var/lib/apt/lists/lock 2>/dev/null)
    LOCK_CMD=$(ps -p $LOCK_PID -o comm= 2>/dev/null)
    echo "⚠️  Apt is locked by process: $LOCK_CMD (PID: $LOCK_PID)."
    echo "    Skipping apt clean to avoid corruption."
else
    apt-get clean
    echo "   Removing unused dependencies (autoremove)..."
    apt-get autoremove -y > /dev/null 2>&1 || echo "⚠️  Autoremove failed (possibly locked). Continuing..."
    echo "✅ Packages Cleaned."
fi
print_freed "$START_SPACE" "$(get_space)"

# 3. Container Runtime Cleanup (CRI)
echo "---"
echo "🐳 CRI Check & Cleanup..."
START_SPACE=$(get_space)
if command -v crictl &> /dev/null; then
    echo "   Pruning dangling images (crictl)..."
    crictl rmi --prune > /dev/null 2>&1 || echo "   (crictl prune warning: check logs)"
else
    echo "   crictl not found. Skipping."
fi
print_freed "$START_SPACE" "$(get_space)"

# 4. BuildKit & Docker Cleanup (The real culprits of T-023)
echo "---"
echo "🏗️  BuildKit / Docker Garbage Collection..."
START_SPACE=$(get_space)

# IF using Docker directly
if command -v docker &> /dev/null; then
    echo "   Docker System Prune (Volumes excluded)..."
    docker system prune -f > /dev/null 2>&1 || echo "   (docker prune warning)"
    
    echo "   Docker Builder Prune (BuildKit cache)..."
    docker builder prune -f --all > /dev/null 2>&1 || echo "   (builder prune warning)"
fi

# IF using standalone BuildKit (nerdctl/rootlesskit context)
# Attempt to find buildctl or related garbage
if command -v buildctl &> /dev/null; then
    echo "   Buildctl Prune..."
    buildctl prune --all --force --keep-storage 1000000000 > /dev/null 2>&1 || echo "   (buildctl prune warning)"
fi
print_freed "$START_SPACE" "$(get_space)"

# 5. Longhorn Orphaned Snapshots (File level check only)
# We can't safely delete Longhorn files from OS side, but we can warn.
LONGHORN_DIR="/var/lib/longhorn"
if [ -d "$LONGHORN_DIR" ]; then
    echo "---"
    echo "💾 Longhorn Storage Check..."
    du -sh "$LONGHORN_DIR" 2>/dev/null || echo "   Unable to read Longhorn dir size."
fi

# 6. Final Report
echo "---"
FINAL_SPACE=$(get_space)
TOTAL_DIFF=$((FINAL_SPACE - INITIAL_SPACE))
echo "✨ Node System Cleanup Complete!"
echo "📈 Total Space Reclaimed: ${TOTAL_DIFF} MB"
df -h / | grep /
