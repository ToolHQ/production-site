#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="${POLICY_FILE:-$SCRIPT_DIR/volume-backup-policy.csv}"
APPLY_CHANGES=false

if [[ "${1:-}" == "--apply" ]]; then
    APPLY_CHANGES=true
    shift
fi

if [[ $# -gt 0 ]]; then
    POLICY_FILE="$1"
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "kubectl not found in PATH" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found in PATH" >&2
    exit 1
fi

if [[ ! -f "$POLICY_FILE" ]]; then
    echo "Policy file not found: $POLICY_FILE" >&2
    exit 1
fi

pv_index=$(kubectl get pv -o json | jq -r '.items[] | select(.spec.csi.volumeHandle != null and .spec.claimRef != null) | [.spec.csi.volumeHandle, .spec.claimRef.namespace, .spec.claimRef.name] | @tsv')

if [[ -z "$pv_index" ]]; then
    echo "No CSI-backed PVs found." >&2
    exit 1
fi

echo "Volume backup policy source: $POLICY_FILE"
if [[ "$APPLY_CHANGES" == true ]]; then
    echo "Mode: apply"
else
    echo "Mode: dry-run"
fi
echo ""

while IFS=, read -r namespace pvc group _notes || [[ -n "${namespace}${pvc}${group}${_notes:-}" ]]; do
    if [[ -z "$namespace" || "${namespace:0:1}" == "#" ]]; then
        continue
    fi

    volume=$(echo "$pv_index" | awk -F'\t' -v target_ns="$namespace" -v target_pvc="$pvc" '$2 == target_ns && $3 == target_pvc { print $1; exit }')
    if [[ -z "$volume" ]]; then
        echo "SKIP  ${namespace}/${pvc} -> volume not found"
        continue
    fi

    cmd=(
        kubectl label volumes.longhorn.io "$volume"
        -n longhorn-system
    )

    if [[ "$group" != "default" ]]; then
        cmd+=(recurring-job-group.longhorn.io/default-)
    fi

    if [[ "$group" != "observability" ]]; then
        cmd+=(recurring-job-group.longhorn.io/observability-)
    fi

    if [[ "$group" != "none" ]]; then
        cmd+=("recurring-job-group.longhorn.io/${group}=enabled" "--overwrite")
    fi

    echo "${namespace}/${pvc} -> ${volume} -> ${group}"
    if [[ "$APPLY_CHANGES" == true ]]; then
        "${cmd[@]}" >/dev/null
        echo "APPLY ${namespace}/${pvc}"
    else
        printf 'DRY   '
        printf '%q ' "${cmd[@]}"
        printf '\n'
    fi
done < "$POLICY_FILE"