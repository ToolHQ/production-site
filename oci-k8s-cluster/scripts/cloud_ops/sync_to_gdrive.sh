#!/bin/bash
# Sync K8s Backups from Minio (Host Mount) to Google Drive
# Running via Systemd Timer

set -e

BACKUP_SRC="/data/minio/k8s-backups"
BACKUP_DEST="gdrive:/k8s-backups"
LOG_FILE="/var/log/gdrive-sync.log"

# Check if rclone is configured
if ! rclone listremotes | grep -q "gdrive:"; then
    echo "$(date): Error - Remote 'gdrive' not configured." >> "$LOG_FILE"
    exit 1
fi

echo "$(date): Starting Sync..." >> "$LOG_FILE"

# Sync with bandwidth limit to be safe
rclone sync "$BACKUP_SRC" "$BACKUP_DEST" \
    --transfers=4 \
    --checkers=8 \
    --bwlimit=5M \
    --log-file="$LOG_FILE" \
    --log-level=INFO

echo "$(date): Sync Complete." >> "$LOG_FILE"
