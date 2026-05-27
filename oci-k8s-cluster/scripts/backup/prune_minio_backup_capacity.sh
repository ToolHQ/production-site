#!/bin/bash
# prune_minio_backup_capacity.sh — Longhorn backup retention enforcement for MinIO headroom (T-304).
#
# Deletes excess backup.longhorn.io CRs (Longhorn GC reclaims backupstore objects).
# Disables recurring backups on postgres replica (redundant with master, T-223).
#
# Usage:
#   ./prune_minio_backup_capacity.sh --dry-run
#   ./prune_minio_backup_capacity.sh --apply
#   ./prune_minio_backup_capacity.sh --apply --retain 3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

RETAIN=3
MODE="dry-run"
POSTGRES_REPLICA_PVC="${POSTGRES_REPLICA_PVC:-pvc-901a3108-754d-4d3e-9133-789189f6e6e7}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) MODE="dry-run"; shift ;;
        --apply) MODE="apply"; shift ;;
        --retain) RETAIN="${2:-3}"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--dry-run|--apply] [--retain N]"
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ -z "${KUBECONFIG:-}" ] && [ -f "$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml" ]; then
    export KUBECONFIG="$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml"
fi

if ! kubectl version --request-timeout=10s >/dev/null 2>&1; then
    echo "❌ kubectl not available. Set KUBECONFIG (tunnel) first." >&2
    exit 1
fi

minio_usage() {
    local pod
    pod=$(kubectl get pod -n minio -l app=minio --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    [ -n "$pod" ] || return 0
    kubectl exec -n minio "$pod" -- sh -c "df -P /data | tail -1; du -sh /data/k8s-backups /data/nexus 2>/dev/null" 2>/dev/null || true
}

echo "=== MinIO backup capacity prune (mode=${MODE}, retain=${RETAIN}) ==="
echo "--- MinIO before ---"
minio_usage
echo ""

BACKUPS_JSON=$(kubectl get backups.longhorn.io -n longhorn-system -o json)
PLAN=$(printf '%s' "$BACKUPS_JSON" | python3 -c "
import json, sys
from collections import defaultdict

retain = int(sys.argv[1])
replica_pvc = sys.argv[2]
data = json.load(sys.stdin)
by = defaultdict(list)
for i in data.get('items', []):
    vol = i.get('metadata', {}).get('labels', {}).get('backup-volume', '?')
    by[vol].append((i['metadata']['creationTimestamp'], i['metadata']['name']))

to_delete = []
disable_replica = 0
for vol in sorted(by):
    items = sorted(by[vol])
    print(f'  {vol}: {len(items)} backup(s)', file=sys.stderr)
    if vol == replica_pvc:
        disable_replica = 1
        for _, name in items:
            to_delete.append(name)
            print(f'  replica purge: {name}', file=sys.stderr)
        continue
    if len(items) <= retain:
        continue
    for _, name in items[: len(items) - retain]:
        to_delete.append(name)
        print(f'  excess prune: {name}', file=sys.stderr)

print('DISABLE_REPLICA=' + str(disable_replica))
for name in to_delete:
    print(name)
" "$RETAIN" "$POSTGRES_REPLICA_PVC")

DISABLE_REPLICA=0
TO_DELETE=()
while IFS= read -r line; do
    if [[ "$line" == DISABLE_REPLICA=* ]]; then
        DISABLE_REPLICA="${line#DISABLE_REPLICA=}"
    elif [ -n "$line" ]; then
        TO_DELETE+=("$line")
    fi
done <<< "$PLAN"

echo ""
echo "Planned deletions: ${#TO_DELETE[@]} backup CR(s)"
if [ "${#TO_DELETE[@]}" -eq 0 ] && [ "$DISABLE_REPLICA" = "0" ]; then
    echo "Nothing to prune."
    exit 0
fi

if [ "$MODE" = "dry-run" ]; then
    printf '  %s\n' "${TO_DELETE[@]}"
    [ "$DISABLE_REPLICA" = "1" ] && echo "  (would disable recurring backup on $POSTGRES_REPLICA_PVC)"
    echo "(dry-run — no changes applied)"
    exit 0
fi

for b in "${TO_DELETE[@]}"; do
    echo "Deleting backup.longhorn.io/$b ..."
    kubectl patch backup.longhorn.io "$b" -n longhorn-system --type=json \
        -p='[{"op":"remove","path":"/metadata/finalizers"}]' 2>/dev/null || true
    kubectl delete backup.longhorn.io "$b" -n longhorn-system --ignore-not-found=true --wait=false
done

if [ "$DISABLE_REPLICA" = "1" ]; then
    echo "Removing recurring-job label from replica volume..."
    kubectl label volume.longhorn.io "$POSTGRES_REPLICA_PVC" -n longhorn-system \
        recurring-job-group.longhorn.io/default- 2>/dev/null || true
fi

echo ""
echo "--- MinIO after (GC may take a minute) ---"
sleep 10
minio_usage
echo "✅ Apply complete."
