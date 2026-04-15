#!/bin/bash
# Sync K8s backups from MinIO on the master node to Google Drive.
# Runs via systemd timer on the master and is safe to execute manually.

set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/data/minio/k8s-backups}"
BACKUP_DEST="${BACKUP_DEST:-gdrive:k8s-backups}"
BACKUPSTORE_DIR="${BACKUPSTORE_DIR:-$BACKUP_ROOT/backupstore}"
ETCD_DIR="${ETCD_DIR:-$BACKUP_ROOT/etcd}"
LOG_FILE="${LOG_FILE:-/var/log/gdrive-sync.log}"
LOCK_FILE="${LOCK_FILE:-/var/lock/gdrive-sync.lock}"

RCLONE_BIN="${RCLONE_BIN:-rclone}"
TRANSFERS="${TRANSFERS:-4}"
CHECKERS="${CHECKERS:-8}"
BWLIMIT="${BWLIMIT:-5M}"
RCLONE_RETRIES="${RCLONE_RETRIES:-3}"
RCLONE_LOW_LEVEL_RETRIES="${RCLONE_LOW_LEVEL_RETRIES:-10}"
ETCD_REMOTE_RETENTION_DAYS="${ETCD_REMOTE_RETENTION_DAYS:-30}"
ETCD_LOCAL_RETENTION_DAYS="${ETCD_LOCAL_RETENTION_DAYS:-7}"

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$LOCK_FILE")"

log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp: $*" | tee -a "$LOG_FILE"
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "Another gdrive sync run is already active. Exiting."
    exit 0
fi

common_rclone_args=(
    "--transfers=${TRANSFERS}"
    "--checkers=${CHECKERS}"
    "--bwlimit=${BWLIMIT}"
    "--retries=${RCLONE_RETRIES}"
    "--low-level-retries=${RCLONE_LOW_LEVEL_RETRIES}"
)

run_rclone_copy() {
    local source_path="$1"
    local destination_path="$2"

    "$RCLONE_BIN" copy "$source_path" "$destination_path" "${common_rclone_args[@]}" >> "$LOG_FILE" 2>&1
}

log "Starting backup archive sync."

if [[ -d "$BACKUPSTORE_DIR" ]]; then
    log "[Job 1/3] Archiving Longhorn backupstore to Google Drive (append-only)."
    # Longhorn backupstore is block-deduplicated. We archive with copy semantics and
    # avoid remote deletes so the offsite copy can serve as a longer-lived archive.
    run_rclone_copy "$BACKUPSTORE_DIR" "${BACKUP_DEST}/backupstore"
else
    log "[Job 1/3] Skipped: ${BACKUPSTORE_DIR} not found."
fi

if [[ -d "$ETCD_DIR" ]]; then
    log "[Job 2/3] Archiving etcd snapshots to Google Drive."
    run_rclone_copy "$ETCD_DIR" "${BACKUP_DEST}/etcd"

    log "[Policy] Pruning Google Drive etcd snapshots older than ${ETCD_REMOTE_RETENTION_DAYS} days."
    "$RCLONE_BIN" delete "${BACKUP_DEST}/etcd" --min-age "${ETCD_REMOTE_RETENTION_DAYS}d" >> "$LOG_FILE" 2>&1

    log "[Job 3/3] Pruning local etcd snapshots older than ${ETCD_LOCAL_RETENTION_DAYS} days."
    find "$ETCD_DIR" -type f -name 'etcd-*.db' -mtime "+${ETCD_LOCAL_RETENTION_DAYS}" -print -delete >> "$LOG_FILE" 2>&1
else
    log "[Job 2/3] Skipped: ${ETCD_DIR} not found."
    log "[Job 3/3] Skipped: ${ETCD_DIR} not found."
fi

log "Backup archive sync complete."
