#!/usr/bin/env bash
# longhorn_headroom_diag.sh — per-node Longhorn + rootfs headroom (T-307)
#
# Usage:
#   ./longhorn_headroom_diag.sh           # human report
#   ./longhorn_headroom_diag.sh --json    # machine-readable
set -euo pipefail

WARN_GB="${LONGHORN_WARN_GB:-15}"
CRIT_GB="${LONGHORN_CRIT_GB:-10}"
JSON=0

for arg in "$@"; do
	case "$arg" in
	--json) JSON=1 ;;
	esac
done

if ! command -v kubectl >/dev/null 2>&1; then
	echo "kubectl required" >&2
	exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
	echo "jq required" >&2
	exit 1
fi

ssh_host_for() {
	case "$1" in
	k8s-master) echo "oci-k8s-master" ;;
	k8s-node-1) echo "oci-k8s-node-1" ;;
	k8s-node-2) echo "oci-k8s-node-2" ;;
	k8s-node-3) echo "oci-k8s-node-3" ;;
	*) echo "$1" ;;
	esac
}

rootfs_avail_gb() {
	local host="$1"
	local kb
	kb="$(ssh -o ConnectTimeout=8 -o BatchMode=yes "$host" \
		"df -P / 2>/dev/null | tail -1 | awk '{print \$4}'" 2>/dev/null || echo 0)"
	echo $((kb / 1024 / 1024))
}

severity_for() {
	local avail_gb="$1" sched="$2"
	if [[ "$sched" != "true" ]]; then
		echo "critical"
	elif ((avail_gb < CRIT_GB)); then
		echo "critical"
	elif ((avail_gb < WARN_GB)); then
		echo "warning"
	else
		echo "ok"
	fi
}

lh_nodes_json="$(kubectl get node.longhorn.io -n longhorn-system -o json 2>/dev/null || echo '{"items":[]}')"

if [[ "$JSON" == "1" ]]; then
	jq -n --argjson nodes "$lh_nodes_json" --argjson warn "$WARN_GB" --argjson crit "$CRIT_GB" '
	  [$nodes.items[] | {
	    node: .metadata.name,
	    schedulable: (.spec.disks | to_entries[0].value.allowScheduling // false),
	    longhorn_avail_bytes: (.status.diskStatus | to_entries[0].value.storageAvailable // 0),
	    longhorn_max_bytes: (.status.diskStatus | to_entries[0].value.storageMaximum // 0),
	    replica_count: ((.status.diskStatus | to_entries[0].value.scheduledReplica // {}) | length)
	  }]
	'
	exit 0
fi

echo "=== Longhorn headroom diagnostic (T-307) ==="
echo "Thresholds: warning < ${WARN_GB}GiB | critical < ${CRIT_GB}GiB | schedulable=false → critical"
echo ""
printf "%-12s %8s %10s %6s %-10s %s\n" "NODE" "ROOT_GB" "LH_GB" "REPL" "SEVERITY" "NOTES"
printf "%-12s %8s %10s %6s %-10s %s\n" "----" "-------" "------" "----" "--------" "-----"

while IFS=$'\t' read -r node sched avail_bytes replica_count; do
	[[ -z "$node" ]] && continue
	avail_gb=$((avail_bytes / 1024 / 1024 / 1024))
	host="$(ssh_host_for "$node")"
	root_gb="$(rootfs_avail_gb "$host")"
	sev="$(severity_for "$avail_gb" "$sched")"
	notes=""
	[[ "$sched" != "true" ]] && notes="scheduling off"
	printf "%-12s %8s %10s %6s %-10s %s\n" "$node" "${root_gb}G" "${avail_gb}G" "$replica_count" "$sev" "$notes"
done < <(echo "$lh_nodes_json" | jq -r '.items[] | [
	.metadata.name,
	(.spec.disks | to_entries[0].value.allowScheduling | tostring),
	(.status.diskStatus | to_entries[0].value.storageAvailable | tostring),
	((.status.diskStatus | to_entries[0].value.scheduledReplica // {}) | length | tostring)
] | @tsv')

echo ""
echo "--- Top volumes by actual size ---"
kubectl get volumes.longhorn.io -n longhorn-system -o json 2>/dev/null | jq -r '
  [.items[] | {
    name: .metadata.name,
    robustness: .status.robustness,
    size_gib: ((.spec.size // 0) / 1073741824),
    actual_gib: ((.status.actualSize // 0) / 1073741824),
    state: .status.state
  }]
  | sort_by(-.actual_gib)
  | .[:8][]
  | "\(.name)\t\(.state)\t\(.robustness)\t\(.actual_gib | floor)GiB actual / \(.size_gib | floor)GiB spec"
' 2>/dev/null | column -t -s $'\t' || echo "(no volumes)"

echo ""
echo "Runbook: oci-k8s-cluster/docs/RUNBOOK_STORAGE_HEADROOM.md"
