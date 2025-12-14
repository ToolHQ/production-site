#!/bin/bash
# clean_node.sh
# Cleans system logs and package cache to reclaim disk space.
# Safe to run on live nodes (does not restart services indiscriminately).

set -e

echo "🧹 Starting System Cleanup..."

# 1. Systemd Journal Logs
echo "---"
echo "📜 Processing System Logs (journalctl)..."
CURRENT_LOG_SIZE=$(du -sh /var/log/journal 2>/dev/null | awk '{print $1}' || echo "N/A")
echo "   Current Size: $CURRENT_LOG_SIZE"
echo "   Vacuuming logs older than 2 days..."
journalctl --vacuum-time=2d
echo "   Vacuuming logs larger than 1G (total)..."
journalctl --vacuum-size=1G
echo "✅ Logs Validated."

# 2. Apt / Package Manager
echo "---"
echo "📦 Processing Package Cache (apt)..."

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
    echo "    This usually means automatic updates are running. Skipping to avoid corruption."
else
    apt-get clean
    echo "   Removing unused dependencies (autoremove)..."
    apt-get autoremove -y || echo "⚠️  Autoremove failed (possibly locked). Continuing..."
    echo "✅ Packages Cleaned."
fi

# 3. Docker/Containerd Prune (Optional - lightweight only)
# We rely on the specific Image Manager for heavy lifting, but we can do build cache.
# echo "---"
# echo "🐳 Pruning Build Cache..."
# crictl does not have build cache prune like docker. Skipping to avoid deleting images.

# 4. Final Report
echo "---"
echo "✨ Node System Cleanup Complete!"
df -h / | grep /
