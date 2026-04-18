#!/bin/bash
set -euo pipefail

APPLY_CHANGES=false

if [[ "${1:-}" == "--apply" ]]; then
    APPLY_CHANGES=true
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found in PATH" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found in PATH" >&2
    exit 1
fi

declare -A current_volumes=()
declare -A backup_counts=()
candidates=()
total_stored=0
total_backups=0

format_gib() {
    awk -v bytes="$1" 'BEGIN { printf "%.2f", bytes / (1024 * 1024 * 1024) }'
}

while read -r volume; do
    if [[ -n "$volume" ]]; then
        current_volumes["$volume"]=1
    fi
done < <(kubectl -n longhorn-system get volumes.longhorn.io -o json | jq -r '.items[].metadata.name')

while IFS=$'\t' read -r owner count; do
    if [[ -n "$owner" ]]; then
        backup_counts["$owner"]="$count"
    fi
done < <(
    kubectl -n longhorn-system get backups.longhorn.io -o json | jq -r '
        [.items[] | .metadata.ownerReferences[0].name // empty]
        | sort
        | group_by(.)
        | .[]
        | "\(.[0])\t\(length)"'
)

echo "Longhorn stale BackupVolume cleanup"
if [[ "$APPLY_CHANGES" == true ]]; then
    echo "Mode: apply"
    echo "This will delete stale BackupVolume CRs and let Longhorn purge their remote backup data."
else
    echo "Mode: dry-run"
fi
echo "Current live volumes: ${#current_volumes[@]}"
echo ""

printf '%-48s %-18s %-30s %-8s %-10s %s\n' \
    "BACKUPVOLUME" "NAMESPACE" "PVC" "BACKUPS" "DATA_GiB" "LAST_BACKUP"

while IFS=$'\t' read -r name volume namespace pvc recurring data_stored last_backup_at; do
    if [[ -n "${current_volumes[$volume]:-}" ]]; then
        continue
    fi

    backup_count="${backup_counts[$name]:-0}"
    printf '%-48s %-18s %-30s %-8s %-10s %s\n' \
        "$name" "$namespace" "$pvc" "$backup_count" "$(format_gib "$data_stored")" "$last_backup_at"

    candidates+=("$name")
    total_stored=$((total_stored + data_stored))
    total_backups=$((total_backups + backup_count))
done < <(
    kubectl -n longhorn-system get backupvolumes.longhorn.io -o json | jq -r '
        .items
        | map(
            (.status.labels.KubernetesStatus? | fromjson? // {}) as $ks
            | {
                name: .metadata.name,
                volume: (.spec.volumeName // ""),
                namespace: ($ks.namespace // "-"),
                pvc: ($ks.pvcName // "-"),
                recurring: (.status.labels.RecurringJob // "-"),
                dataStored: ((.status.dataStored // "0") | tonumber),
                lastBackupAt: (.status.lastBackupAt // "-")
            }
        )
        | sort_by(-.dataStored, .lastBackupAt)
        | .[]
        | [.name, .volume, .namespace, .pvc, .recurring, (.dataStored | tostring), .lastBackupAt]
        | @tsv'
)

echo ""
echo "Stale BackupVolumes: ${#candidates[@]}"
echo "Stale backups: $total_backups"
echo "Estimated dataStored: $(format_gib "$total_stored") GiB"
echo ""

if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "No stale BackupVolume objects found."
    exit 0
fi

if [[ "$APPLY_CHANGES" == true ]]; then
    for candidate in "${candidates[@]}"; do
        echo "DELETE $candidate"
        kubectl -n longhorn-system delete backupvolumes.longhorn.io "$candidate"
    done
else
    echo "Dry-run only. Re-run with --apply after confirming these historical generations have no restore value."
fi