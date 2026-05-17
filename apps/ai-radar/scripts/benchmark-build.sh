#!/usr/bin/env bash
# Benchmark AI Radar API build: Hetzner vs baseline expectations.
# Usage: ./scripts/benchmark-build.sh [hetzner|oci]
set -euo pipefail

MODE="${1:-hetzner}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
DOCKERFILE="$ROOT_DIR/docker/Dockerfile"
TAG="bench-$(date +%s)"
REGISTRY='registry.local:31444/repository/docker-repo'
IMAGE_API="$REGISTRY/my-site-ai-radar-api:$TAG"

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*"; }
sec() { date +%s; }

master_stats() {
	ssh -o BatchMode=yes oci-k8s-master bash -s <<'REMOTE' 2>/dev/null || echo "master_ssh_failed"
df -h / | tail -1
sudo du -sh /var/lib/buildkit 2>/dev/null || echo "buildkit 0"
REMOTE
}

hetzner_stats() {
	ssh -o BatchMode=yes hetzner-cax21-helsinki-4vcpu-8gb-ipv4 bash -s <<'REMOTE' 2>/dev/null || echo "hetzner_ssh_failed"
df -h / | tail -1
docker system df 2>/dev/null | head -5
REMOTE
}

run_build() {
	local builder="$1" label="$2" extra_flags=("${@:3}")
	local t0 t1
	log "=== BUILD $label (builder=$builder) ==="
	t0=$(sec)
	# shellcheck disable=SC2068
	docker buildx build \
		--builder "$builder" \
		--platform linux/arm64 \
		"${extra_flags[@]}" \
		-f "$DOCKERFILE" \
		--target runtime-api \
		--build-arg BIN_NAME=ai-radar-api \
		-t "$IMAGE_API" \
		"$ROOT_DIR"
	t1=$(sec)
	log "BUILD $label elapsed: $((t1 - t0))s ($(( (t1 - t0) / 60 ))m)"
	echo "$((t1 - t0))"
}

log "Benchmark mode: $MODE"
log "Image tag: $IMAGE_API"
log "--- Master antes ---"
master_stats
log "--- Hetzner antes ---"
hetzner_stats

if [[ "$MODE" == "hetzner" ]]; then
	HETZNER_SETUP="$REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh"
	"$HETZNER_SETUP" --silent
	warm1=$(run_build hetzner-builder "hetzner-run1" --load)
	warm2=$(run_build hetzner-builder "hetzner-run2-cache" --load)
	log "Cache speedup: run1=${warm1}s run2=${warm2}s"
	if ! ss -tlnp 2>/dev/null | grep -q ':31444'; then
		ssh -o StrictHostKeyChecking=no -L 31444:localhost:31444 oci-k8s-master -N -f
		sleep 1
	fi
	LOCAL="localhost:31444/repository/docker-repo/my-site-ai-radar-api:$TAG"
	docker tag "$IMAGE_API" "$LOCAL"
	t0=$(sec)
	docker push "$LOCAL" >/dev/null
	t1=$(sec)
	log "PUSH to Nexus elapsed: $((t1 - t0))s"
	docker rmi "$LOCAL" >/dev/null 2>&1 || true
	docker image inspect "$IMAGE_API" --format 'size={{.Size}} arch={{.Architecture}}' 2>/dev/null || true
elif [[ "$MODE" == "oci" ]]; then
	run_build oci-builder "oci-master" --push
else
	echo "Usage: $0 [hetzner|oci]" >&2
	exit 1
fi

log "--- Master depois ---"
master_stats
log "--- Hetzner depois ---"
hetzner_stats
log "Done."
