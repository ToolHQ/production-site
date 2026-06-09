#!/usr/bin/env bash
# deploy-buildx.sh — Hetzner-first buildx; build no OCI master só com ALLOW_MASTER_BUILD=1.
#
# Uso (source em deploy bash):
#   source "$REPO_ROOT/oci-k8s-cluster/scripts/lib/deploy-buildx.sh"
#   deploy_select_buildx_builder
#   deploy_buildx_push_images "$SERVICE" "$IMAGE_TAG" "$IMAGE_LATEST" "$CONTEXT" -- [extra buildx args]
#
# Uso (CLI a partir de deploy.sh POSIX):
#   bash "$REPO_ROOT/oci-k8s-cluster/scripts/lib/deploy-buildx.sh" build-push \
#     --service SVC --image-tag TAG --image-latest LATEST --context-dir DIR -- [extra args]
#
# Emergência no master (pré-voo de disco):
#   ALLOW_MASTER_BUILD=1 ./deploy.sh
#   (alias legado: AI_RADAR_ALLOW_MASTER_BUILD=1)

set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$_LIB_DIR/../../.." && pwd)}"

USE_HETZNER="${USE_HETZNER:-false}"

deploy_allow_master_build() {
	[[ "${ALLOW_MASTER_BUILD:-${AI_RADAR_ALLOW_MASTER_BUILD:-0}}" =~ ^(1|true|yes)$ ]]
}

# Pré-voo disco no nó do buildkitd do master (só quando build no oci-builder).
deploy_preflight_buildkit_disk() {
	local host="${OCI_BUILDKIT_HOST:-oci-k8s-master}"
	local min_gb="${BUILD_MIN_FREE_GB:-${AI_RADAR_BUILD_MIN_FREE_GB:-12}}"
	local out avail_kb avail_gb buildkit_du buildkit_gb

	out="$(ssh -o BatchMode=yes "${host}" bash -s <<'REMOTE'
set -e
avail_kb=$(df -k / | tail -1 | awk '{print $4}')
buildkit_du=$(sudo du -sk /var/lib/buildkit 2>/dev/null | awk '{print $1}' || echo 0)
echo "$avail_kb $buildkit_du"
REMOTE
)" || {
		echo "❌ pré-voo: não foi possível checar disco/buildkit em $host (SSH?)" >&2
		return 1
	}

	avail_kb="$(echo "$out" | awk '{print $1}')"
	buildkit_du="$(echo "$out" | awk '{print $2}')"
	avail_gb=$((avail_kb / 1024 / 1024))
	buildkit_gb=$((buildkit_du / 1024 / 1024))

	echo "📏 pré-voo buildkit ($host): / livre ≈ ${avail_gb} GiB | cache buildkit ≈ ${buildkit_gb} GiB (mín. livre ${min_gb} GiB)" >&2

	if [[ "$avail_gb" -lt "$min_gb" ]]; then
		if [[ "$buildkit_gb" -ge 3 ]] && [[ "${BUILDKIT_PRUNE:-${AI_RADAR_BUILDKIT_PRUNE:-0}}" =~ ^(1|true|yes)$ ]]; then
			echo "⚠️  livre < ${min_gb} GiB — prune automático (BUILDKIT_PRUNE=1)…" >&2
			ssh -o BatchMode=yes "$host" \
				'sudo buildctl --addr unix:///run/buildkit/buildkitd.sock prune --all' >/dev/null \
				|| {
					echo "❌ prune buildkit falhou" >&2
					return 1
				}
			out="$(ssh -o BatchMode=yes "$host" 'df -k / | tail -1 | awk "{print \$4}"')"
			avail_gb=$((out / 1024 / 1024))
			echo "   após prune: / livre ≈ ${avail_gb} GiB" >&2
		fi
		if [[ "$avail_gb" -lt "$min_gb" ]]; then
			echo "❌ disco insuficiente no $host (~${avail_gb} GiB livres; precisa ≥ ${min_gb} GiB)." >&2
			echo "   Rode no master: sudo buildctl --addr unix:///run/buildkit/buildkitd.sock prune --all" >&2
			echo "   Ou: BUILDKIT_PRUNE=1 ALLOW_MASTER_BUILD=1 ./deploy.sh" >&2
			return 1
		fi
	fi
}

# Tenta hetzner-builder; master só com ALLOW_MASTER_BUILD=1. Exporta USE_HETZNER=true|false.
deploy_select_buildx_builder() {
	local hetzner_setup="$REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh"
	USE_HETZNER=false

	if [[ -f "$hetzner_setup" ]] && "$hetzner_setup" --silent; then
		USE_HETZNER=true
		echo "✓ hetzner-builder ativo — build ARM64 na Hetzner (master preservado)" >&2
	elif deploy_allow_master_build; then
		echo "⚠️  ALLOW_MASTER_BUILD=1 — build no oci-builder do master (disco + prune)" >&2
		deploy_preflight_buildkit_disk
	else
		echo "❌ hetzner-builder indisponível e build no master está desabilitado por padrão." >&2
		echo "   Diagnóstico: $REPO_ROOT/oci-k8s-cluster/scripts/check-hetzner-builder.sh" >&2
		echo "   Setup: $hetzner_setup" >&2
		echo "   Ou emergência: ALLOW_MASTER_BUILD=1 ./deploy.sh" >&2
		return 1
	fi
	export USE_HETZNER
}

deploy_ensure_registry_tunnel() {
	if ! ss -tlnp 2>/dev/null | grep -q ':31444'; then
		echo "🔌 Garantindo túnel SSH para o registro local (porta 31444)..." >&2
		ssh -o StrictHostKeyChecking=no -L 31444:localhost:31444 oci-k8s-master -N -f
		sleep 1
	fi
}

# deploy_buildx_push_images SERVICE IMAGE_TAG IMAGE_LATEST CONTEXT [-- extra docker buildx args]
# Requer deploy_select_buildx_builder antes (define USE_HETZNER).
deploy_buildx_push_images() {
	local service="$1" image_tag="$2" image_latest="$3" context="$4"
	shift 4

	if [[ "$USE_HETZNER" == "true" ]]; then
		echo "🚀 Usando builder Hetzner remoto de alta performance..." >&2
		docker buildx build \
			--builder hetzner-builder \
			--platform linux/arm64 \
			--load \
			-t "$image_tag" \
			-t "$image_latest" \
			"$@" \
			"$context"

		deploy_ensure_registry_tunnel

		local tag_version="${image_tag##*:}"
		local local_tag="localhost:31444/repository/docker-repo/${service}:${tag_version}"
		local local_latest="localhost:31444/repository/docker-repo/${service}:latest"
		docker tag "$image_tag" "$local_tag"
		docker tag "$image_latest" "$local_latest"

		echo "⬆️ Enviando imagem ao registro local (túnel 31444)..." >&2
		docker push "$local_tag"
		docker push "$local_latest"
		docker rmi "$local_tag" "$local_latest" >/dev/null 2>&1 || true
	else
		echo "⚠️ Build no oci-builder do master (emergência)..." >&2
		docker buildx build \
			--builder oci-builder \
			--platform linux/arm64 \
			--push \
			-t "$image_tag" \
			-t "$image_latest" \
			"$@" \
			"$context"
	fi
}

# Imprime USE_HETZNER=... para eval em deploy.sh POSIX
_cmd_export_builder_env() {
	deploy_select_buildx_builder
	printf 'USE_HETZNER=%s\n' "$USE_HETZNER"
}

_cmd_build_push() {
	local service="" image_tag="" image_latest="" context_dir="."
	local -a extra_args=()
	local parsing_extra=false

	while [[ $# -gt 0 ]]; do
		if [[ "$parsing_extra" == "true" ]]; then
			extra_args+=("$1")
			shift
			continue
		fi
		case "$1" in
		--service) service="$2"; shift 2 ;;
		--image-tag) image_tag="$2"; shift 2 ;;
		--image-latest) image_latest="$2"; shift 2 ;;
		--context-dir) context_dir="$2"; shift 2 ;;
		--) parsing_extra=true; shift ;;
		*) echo "argumento desconhecido: $1" >&2; return 2 ;;
		esac
	done

	[[ -n "$service" && -n "$image_tag" && -n "$image_latest" ]] || {
		echo "uso: deploy-buildx.sh build-push --service SVC --image-tag TAG --image-latest LATEST [--context-dir DIR] -- [buildx args]" >&2
		return 2
	}

	deploy_select_buildx_builder
	deploy_buildx_push_images "$service" "$image_tag" "$image_latest" "$context_dir" "${extra_args[@]}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	case "${1:-}" in
	export-builder-env)
		shift
		_cmd_export_builder_env "$@"
		;;
	build-push)
		shift
		_cmd_build_push "$@"
		;;
	*)
		echo "comandos: export-builder-env | build-push" >&2
		exit 2
		;;
	esac
fi
