#!/bin/bash
# scripts/maintenance/storage_watchdog.sh
# Checks disk usage and triggers incremental cleanup to prevent DiskPressure.
# Intended to be run via Cron (e.g., every 5-10 mins).

# Thresholds
THRESH_LIGHT=85 # % Usage to trigger logs cleanup
THRESH_DEEP=90  # % Usage to trigger full cleanup

# Paths
CLEANER_SCRIPT="/usr/local/bin/clean_node.sh"
LOG_TAG="storage-watchdog"

# Lock file to prevent concurrent runs
LOCK_FILE="/var/tmp/storage_watchdog.lock"
exec 200>$LOCK_FILE
flock -n 200 || exit 1

# Get Current Usage (Root partition)
# df output: /dev/sda1 40G 30G 10G 75% /
USAGE=$(df -P / | awk 'NR==2 {print $5}' | tr -d '%')

if [ "$USAGE" -ge "$THRESH_DEEP" ]; then
    logger -t $LOG_TAG "CRITICAL: Disk Usage at ${USAGE}%. Triggering DEEP cleanup."
    if [ -x "$CLEANER_SCRIPT" ]; then
        $CLEANER_SCRIPT --deep >> /var/log/syslog 2>&1
    fi
    
elif [ "$USAGE" -ge "$THRESH_LIGHT" ]; then
    logger -t $LOG_TAG "WARNING: Disk Usage at ${USAGE}%. Triggering LIGHT cleanup."
    if [ -x "$CLEANER_SCRIPT" ]; then
        $CLEANER_SCRIPT --light >> /var/log/syslog 2>&1
    fi
fi
# Else: Do nothing, system is healthy
