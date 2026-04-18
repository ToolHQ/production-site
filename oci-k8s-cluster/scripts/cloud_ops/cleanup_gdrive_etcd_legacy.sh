#!/bin/bash
# Prepare and optionally execute cleanup of legacy ETCD artifacts in Google Drive.
# Default mode is dry-run. Use --apply only after reviewing the candidate set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../common.sh"

MASTER="${MASTER_NODE:-oci-k8s-master}"
REMOTE="${REMOTE:-gdrive:k8s-backups/etcd}"
RCLONE_CONFIG="${RCLONE_CONFIG:-/root/.config/rclone/rclone.conf}"
APPLY=false

if [[ "${1:-}" == "--apply" ]]; then
    APPLY=true
fi

DRY_RUN_FLAG="-n"
if [[ "$APPLY" == true ]]; then
    DRY_RUN_FLAG=""
fi

LEGACY_DIRS=(
    "etcd-20260112-131425.db/"
    "etcd-20260112-131444.db/"
    "etcd-20260415-164937.db/"
    "etcd-20260415-180005.db/"
    "etcd-20260416-000005.db/"
    "etcd-20260416-060005.db/"
    "perm-check-1776270602.txt/"
    "test-write.txt/"
)

LEGACY_FILES=(
    "latest_snapshot"
)

run_remote_rclone() {
    ssh "$MASTER" "sudo rclone $* --config $RCLONE_CONFIG"
}

echo "Google Drive ETCD legacy cleanup"
echo "  Remote: $REMOTE"
if [[ "$APPLY" == true ]]; then
    echo "  Mode: apply"
else
    echo "  Mode: dry-run"
fi
echo ""

echo "Current remote entries:"
run_remote_rclone lsf "$REMOTE" --format "pst" | sort
echo ""

echo "Directory purge candidates:"
for candidate in "${LEGACY_DIRS[@]}"; do
    echo "  - $candidate"
done
echo ""

echo "File delete candidates:"
for candidate in "${LEGACY_FILES[@]}"; do
    echo "  - $candidate"
done
echo ""

echo "Purging legacy directories..."
for candidate in "${LEGACY_DIRS[@]}"; do
    if [[ -n "$DRY_RUN_FLAG" ]]; then
        run_remote_rclone purge "$DRY_RUN_FLAG" "$REMOTE/$candidate"
    else
        run_remote_rclone purge "$REMOTE/$candidate"
    fi
done
echo ""

echo "Deleting legacy files..."
for candidate in "${LEGACY_FILES[@]}"; do
    if [[ -n "$DRY_RUN_FLAG" ]]; then
        run_remote_rclone deletefile "$DRY_RUN_FLAG" "$REMOTE/$candidate"
    else
        run_remote_rclone deletefile "$REMOTE/$candidate"
    fi
done
echo ""

echo "Deduping remaining file-name collisions..."
if [[ -n "$DRY_RUN_FLAG" ]]; then
    run_remote_rclone dedupe "$DRY_RUN_FLAG" --dedupe-mode first "$REMOTE"
else
    run_remote_rclone dedupe --dedupe-mode first "$REMOTE"
fi

echo ""
echo "Cleanup routine finished."