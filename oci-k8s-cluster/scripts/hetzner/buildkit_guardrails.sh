#!/usr/bin/env bash
# buildkit_guardrails.sh — prune/reset BuildKit cache on Hetzner builder (T-311)
#
# Installed by install_buildkit_guardrails.sh as a systemd timer (every 6h).
# Safe defaults: prune first; reset container+volume only when buildkit data
# exceeds MAX_BUILDKIT_GB or rootfs exceeds MAX_USED_PCT.
#
# Usage:
#   buildkit_guardrails.sh              # apply policy
#   buildkit_guardrails.sh --dry-run    # log actions only
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
	case "$arg" in
	--dry-run) DRY_RUN=1 ;;
	esac
done

MAX_USED_PCT="${MAX_USED_PCT:-75}"
MAX_BUILDKIT_GB="${MAX_BUILDKIT_GB:-16}"
BUILDER_NAME="${BUILDER_NAME:-hetzner-builder}"
CONTAINER="buildx_buildkit_${BUILDER_NAME}0"
VOLUME="buildx_buildkit_${BUILDER_NAME}0_state"
LOG="${BUILDKIT_GUARDRAILS_LOG:-/var/log/buildkit-guardrails.log}"

log() {
	local ts msg
	ts="$(date -Iseconds)"
	msg="[$ts] $*"
	echo "$msg"
	echo "$msg" >>"$LOG"
}

run() {
	if [[ "$DRY_RUN" == "1" ]]; then
		log "DRY-RUN: $*"
	else
		log "exec: $*"
		"$@"
	fi
}

used_pct=$(df -P / | tail -1 | awk '{gsub(/%/,"",$5); print $5}')
log "rootfs used=${used_pct}% (max=${MAX_USED_PCT}%)"

if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
	if [[ "$DRY_RUN" == "1" ]]; then
		log "DRY-RUN: docker buildx prune --all --force --max-storage ${MAX_BUILDKIT_GB}gb"
	else
		docker buildx prune --all --force --max-storage "${MAX_BUILDKIT_GB}gb" >/dev/null 2>&1 || true
	fi

	bk_gb=$(docker exec "${CONTAINER}" sh -c "du -sk /var/lib/buildkit 2>/dev/null | awk '{print int(\$1/1024/1024)}'" 2>/dev/null || echo 0)
	log "buildkit data ~= ${bk_gb}GiB (max=${MAX_BUILDKIT_GB}GiB)"

	need_reset=0
	if [[ "${bk_gb}" -ge "${MAX_BUILDKIT_GB}" ]]; then
		need_reset=1
		log "buildkit above size threshold"
	fi
	if [[ "${used_pct}" -ge "${MAX_USED_PCT}" ]]; then
		need_reset=1
		log "rootfs above usage threshold"
	fi

	if [[ "$need_reset" == "1" ]]; then
		log "resetting buildkit container+volume"
		if [[ "$DRY_RUN" == "1" ]]; then
			log "DRY-RUN: docker rm -f ${CONTAINER}; docker volume rm ${VOLUME}"
		else
			docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
			docker volume rm "${VOLUME}" >/dev/null 2>&1 || true
		fi
	fi
else
	log "buildkit container ${CONTAINER} not found; skipping"
fi

df -h / | tail -1 | awk '{print "rootfs: "$2" total, "$3" used, "$4" avail ("$5")"}' | while read -r line; do log "$line"; done
docker system df 2>/dev/null | while read -r line; do log "$line"; done
log "done"
