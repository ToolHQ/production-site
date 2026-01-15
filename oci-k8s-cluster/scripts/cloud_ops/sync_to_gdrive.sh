#!/bin/bash
# Sync K8s Backups from Minio (Host Mount) to Google Drive
# Running via Systemd Timer

set -e

BACKUP_SRC="/data/minio/k8s-backups"
BACKUP_DEST="gdrive:/k8s-backups"
LOG_FILE="/var/log/gdrive-sync.log"

LOG_FILE="./gdrive-sync.log"

echo "$(date '+%Y-%m-%d %H:%M:%S'): Starting Backup Routine..." >> "$LOG_FILE"

# ---------------------------------------------------------
# 1. MIRROR STRATEGY (Longhorn, Nexus)
# Integrity is priority. GDrive reflects Minio exactly.
# Exclude 'etcd' because we want to treat it differently (Archive).
# ---------------------------------------------------------
echo "$(date '+%Y-%m-%d %H:%M:%S'): [Job 1/3] Syncing General Backups (Longhorn/Nexus)..." >> "$LOG_FILE"
rclone sync "$BACKUP_SRC" "$BACKUP_DEST" \
    --exclude "/etcd/**" \
    --transfers=4 \
    --checkers=8 \
    --bwlimit=5M \
    >> "$LOG_FILE" 2>&1

# ---------------------------------------------------------
# 2. ARCHIVE STRATEGY (Etcd)
# We want longer history on Cloud (30d) vs Local (7d).
# ---------------------------------------------------------
echo "$(date '+%Y-%m-%d %H:%M:%S'): [Job 2/3] Archiving Etcd (Copy + Cloud Retention)..." >> "$LOG_FILE"

# Step A: Copy new files (Do NOT delete anything on GDrive yet)
rclone copy "$BACKUP_SRC/etcd" "$BACKUP_DEST/etcd" >> "$LOG_FILE" 2>&1

# Step B: Apply Cloud Retention (Delete GDrive files older than 30 days)
echo "$(date '+%Y-%m-%d %H:%M:%S'): [Policy] Pruning GDrive Etcd > 30 days..." >> "$LOG_FILE"
rclone delete "$BACKUP_DEST/etcd" --min-age 30d >> "$LOG_FILE" 2>&1

# ---------------------------------------------------------
# 3. LOCAL CLEANUP (Free up Minio Space)
# ---------------------------------------------------------
echo "$(date '+%Y-%m-%d %H:%M:%S'): [Job 3/3] Pruning Local Etcd > 7 days..." >> "$LOG_FILE"
# Only delete if we successfully uploaded (rclone exit code 0 preferred, but 'set -e' handles failures above)
# Finding and deleting local Etcd snapshots older than 7 days
find "$BACKUP_SRC/etcd" -type f -name "etcd-*.db" -mtime +7 -exec rm -v {} \; >> "$LOG_FILE" 2>&1

echo "$(date '+%Y-%m-%d %H:%M:%S'): Backup Routine Complete." >> "$LOG_FILE"
