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

echo "---"
echo "📝 Processing Rsyslog Files..."
START_SPACE=$(get_space)
for log_file in \
    /var/log/syslog \
    /var/log/syslog.1 \
    /var/log/auth.log \
    /var/log/auth.log.1 \
    /var/log/kern.log \
    /var/log/kern.log.1 \
    /var/log/daemon.log \
    /var/log/daemon.log.1; do
    [ -f "$log_file" ] || continue
    file_size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
    if [ "$file_size" -gt $((1024 * 1024 * 1024)) ]; then
        echo "   Truncating $(basename "$log_file") ($(du -h "$log_file" | awk '{print $1}'))..."
        truncate -s 0 "$log_file" 2>/dev/null || true
    fi
done
find /var/log -maxdepth 1 \
    \( -name 'syslog.*.gz' -o -name 'auth.log.*.gz' -o -name 'kern.log.*.gz' -o -name 'daemon.log.*.gz' \) \
    -mtime +2 -delete 2>/dev/null || true
echo "✅ Rsyslog Files Checked."
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
    # Snapd Cleanup
    echo "---"
    echo "🥦 Snap Clean..."
    if command -v snap >/dev/null; then
        # Clean up disabled snaps
        set +e
        LANG=C snap list --all | awk '/disabled/{print $1, $3}' |
            while read snapname revision; do
                echo "   Removing $snapname (revision $revision)..."
                snap remove "$snapname" --revision="$revision" > /dev/null 2>&1
            done
        # Clean cache
        rm -rf /var/lib/snapd/cache/*
        echo "✅ Snap Cache Cleaned."
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
        buildctl prune --all --force --keep-storage 1000000000 > /dev/null 2>&1 || true
    fi

    ROOTLESS_BUILDKIT_USER="ubuntu"
    ROOTLESS_BUILDKIT_BIN="/home/${ROOTLESS_BUILDKIT_USER}/bin/buildctl"
    ROOTLESS_BUILDKIT_SOCK="/home/${ROOTLESS_BUILDKIT_USER}/.local/share/buildkit/buildkitd.sock"
    ROOTLESS_BUILDKIT_DIR="/home/${ROOTLESS_BUILDKIT_USER}/.local/share/buildkit"
    if id "$ROOTLESS_BUILDKIT_USER" >/dev/null 2>&1 && [ -x "$ROOTLESS_BUILDKIT_BIN" ]; then
        echo "   Rootless BuildKit Prune (${ROOTLESS_BUILDKIT_USER})..."
        ROOTLESS_UID=$(id -u "$ROOTLESS_BUILDKIT_USER")
        if [ -S "$ROOTLESS_BUILDKIT_SOCK" ]; then
            sudo -u "$ROOTLESS_BUILDKIT_USER" \
                XDG_RUNTIME_DIR="/run/user/${ROOTLESS_UID}" \
                "$ROOTLESS_BUILDKIT_BIN" \
                --addr "unix://${ROOTLESS_BUILDKIT_SOCK}" \
                prune --all --force --keep-storage 1000000000 > /dev/null 2>&1 || true
        elif pgrep -u "$ROOTLESS_BUILDKIT_USER" -f buildkitd >/dev/null 2>&1; then
            echo "   Rootless BuildKit daemon active without socket path; skipping offline cleanup."
        elif [ -d "$ROOTLESS_BUILDKIT_DIR" ]; then
            echo "   Rootless BuildKit daemon inactive; clearing stale cache directory..."
            find "$ROOTLESS_BUILDKIT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true
        else
            echo "   Rootless BuildKit socket not present; skipping live prune."
        fi
    fi
    print_freed "$START_SPACE" "$(get_space)"

    # 5. GHOST DATA CLEANUP (Orphaned /var/lib/docker)
    # Detect if we are using Containerd but have leftover Docker data
    if [ -d "/var/lib/docker" ] && ! pgrep -x "dockerd" >/dev/null; then
        echo "---"
        echo "👻 Ghost Docker Data Detected..."
        GHOST_SIZE=$(du -sh /var/lib/docker 2>/dev/null | awk '{print $1}')
        echo "   Found $GHOST_SIZE in /var/lib/docker (Daemon inactive)."
        
        # Double check that we are not just failing to connect, but that containerd IS running
        if command -v crictl >/dev/null && crictl info >/dev/null 2>&1; then
             echo "   ✅ Containerd is active. Safe to purge Docker artifacts."
             rm -rf /var/lib/docker/*
             echo "   ✨ Purged $GHOST_SIZE of orphan data."
        else
             echo "   ⚠️  Containerd not verified or active. Skipping purge for safety."
        fi
    fi
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
