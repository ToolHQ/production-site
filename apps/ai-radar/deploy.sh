#!/usr/bin/env bash
# OCI Deploy — my-site-ai-radar-api (Kustomize overlay production).
#
# Fluxo rápido (ver README):
#   source ~/production-site/oci-k8s-cluster/scripts/setup-dev-deploy.sh
#   export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
#
# Secret DATABASE_URL não está no Git (nem no Kustomize). Escolha UMA forma:
#
#   1. Deixar o secret já aplicado neste cluster (kubectl / SealedSecret / SOPS).
#   2. export AI_RADAR_DATABASE_URL='postgres://…'
#   3. export AI_RADAR_FROM_CLUSTER_PG_SECRET=1
#       → monta DATABASE_URL via Secret postgres postgres-secret (credenciais
#       de administração do cluster shared Postgres — database default `postgres`).
#       Migrações ainda devem poder executar DDL (primário gravável).

set -euo pipefail

TAG_VERSION="$(date +%s)"
REGISTRY='registry.local:31444'
REPO='repository/docker-repo'
SERVICE_API='my-site-ai-radar-api'
SERVICE_CLI='my-site-ai-radar-cli'

IMAGE_API_TAG="$REGISTRY/$REPO/$SERVICE_API:$TAG_VERSION"
IMAGE_API_LATEST="$REGISTRY/$REPO/$SERVICE_API:latest"
IMAGE_CLI_TAG="$REGISTRY/$REPO/$SERVICE_CLI:$TAG_VERSION"
IMAGE_CLI_LATEST="$REGISTRY/$REPO/$SERVICE_CLI:latest"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"

die() {
	printf '%s\n' "$*" >&2
	exit 1
}

if ! kubectl get ns >/dev/null 2>&1; then
	die "❌ kubectl indisponível ou tunnel inativo. rode setup-dev-deploy.sh + export KUBECONFIG tunnel."
fi

kubectl apply -f "$ROOT_DIR/k8s/base/namespace.yaml"

"${REPO_ROOT}/components/nexus/create_registry_secret.sh" ai-radar 2>/dev/null \
	| kubectl apply -f -

if kubectl get secret ai-radar-database -n ai-radar >/dev/null 2>&1; then
	:
elif [[ -n "${AI_RADAR_DATABASE_URL:-}" ]]; then
	kubectl create secret generic ai-radar-database -n ai-radar \
		--from-literal='DATABASE_URL'="$AI_RADAR_DATABASE_URL" \
		--dry-run=client -o yaml | kubectl apply -f -
elif [[ "${AI_RADAR_FROM_CLUSTER_PG_SECRET:-0}" =~ ^(1|true|yes)$ ]]; then
	URL="$(
		env \
			AI_RADAR_PG_HOST="${AI_RADAR_PG_HOST:-}" \
			AI_RADAR_PG_PORT="${AI_RADAR_PG_PORT:-}" \
			AI_RADAR_PG_DATABASE="${AI_RADAR_PG_DATABASE:-}" \
			python3 "$ROOT_DIR/scripts/render-ai-radar-database-url.py"
	)"
	kubectl create secret generic ai-radar-database -n ai-radar \
		--from-literal='DATABASE_URL'="$URL" \
		--dry-run=client -o yaml | kubectl apply -f -
else
	cat <<'TXT' >&2
❌ Secret ai-radar-database ausente neste cluster.

Escolha:
  AI_RADAR_DATABASE_URL='postgres://…' ./deploy.sh
  AI_RADAR_FROM_CLUSTER_PG_SECRET=1 ./deploy.sh   ← usa kubectl + postgres postgres-secret

(Detalhes: README apps/ai-radar — migrações exigem primário Postgres gravável.)
TXT
	exit 1
fi

warn_postgres_standby_loop() {
	local pu pp out
	pu="$(kubectl get secret postgres-secret -n postgres -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)"
	pp="$(kubectl get secret postgres-secret -n postgres -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
	out="$(kubectl exec -n postgres postgres-0 -- env PGPASSWORD="$pp" psql -U "$pu" -d postgres -tAc 'select pg_is_in_recovery()' 2>/dev/null || true)"
	if [[ "$(echo "${out:-}" | tr -d '[:space:]')" == 't' ]]; then
		printf '%s\n' '⚠️  postgres-0 relatou pg_is_in_recovery()=true → cluster possivelmente sem primário;' \
			'   DDL/migrations e primeira subida íntegra do schema podem falhar até infra (ex. T-190).' >&2
	fi
}

if kubectl get pod postgres-0 -n postgres >/dev/null 2>&1; then
	warn_postgres_standby_loop || true
fi

# Pré-voo: disco no nó do buildkitd (build Rust ARM64 usa pico alto de snapshots).
# Estimativa empírica (oci-k8s-master): ~8–12 GiB cache BuildKit + pico ~6–10 GiB no link
# (aws-lc-sys); duas imagens (api + cli) em sequência. Mínimo recomendado: 12 GiB livres em / (pós T-193).
preflight_buildkit_disk() {
	local host="${OCI_BUILDKIT_HOST:-oci-k8s-master}"
	local min_gb="${AI_RADAR_BUILD_MIN_FREE_GB:-12}"
	local out avail_kb avail_gb buildkit_du buildkit_gb

	out="$(ssh -o BatchMode=yes "${host}" bash -s <<'REMOTE'
set -e
avail_kb=$(df -k / | tail -1 | awk '{print $4}')
buildkit_du=$(sudo du -sk /var/lib/buildkit 2>/dev/null | awk '{print $1}' || echo 0)
echo "$avail_kb $buildkit_du"
REMOTE
)" || die "❌ pré-voo: não foi possível checar disco/buildkit em $host (SSH?)"

	avail_kb="$(echo "$out" | awk '{print $1}')"
	buildkit_du="$(echo "$out" | awk '{print $2}')"
	avail_gb=$((avail_kb / 1024 / 1024))
	buildkit_gb=$((buildkit_du / 1024 / 1024))

	printf '%s\n' "📏 pré-voo buildkit ($host): / livre ≈ ${avail_gb} GiB | cache buildkit ≈ ${buildkit_gb} GiB (mín. livre ${min_gb} GiB; pico Rust ~14–22 GiB)"

	if [[ "$avail_gb" -lt "$min_gb" ]]; then
		if [[ "$buildkit_gb" -ge 3 ]] && [[ "${AI_RADAR_BUILDKIT_PRUNE:-0}" =~ ^(1|true|yes)$ ]]; then
			printf '%s\n' "⚠️  livre < ${min_gb} GiB — prune automático (AI_RADAR_BUILDKIT_PRUNE=1)…" >&2
			ssh -o BatchMode=yes "$host" \
				'sudo buildctl --addr unix:///run/buildkit/buildkitd.sock prune --all' >/dev/null \
				|| die "❌ prune buildkit falhou"
			out="$(ssh -o BatchMode=yes "$host" 'df -k / | tail -1 | awk "{print \$4}"')"
			avail_gb=$((out / 1024 / 1024))
			printf '%s\n' "   após prune: / livre ≈ ${avail_gb} GiB"
		fi
		if [[ "$avail_gb" -lt "$min_gb" ]]; then
			die "❌ disco insuficiente no $host (~${avail_gb} GiB livres; precisa ≥ ${min_gb} GiB).
   Rode no master: sudo buildctl --addr unix:///run/buildkit/buildkitd.sock prune --all
   Ou: AI_RADAR_BUILDKIT_PRUNE=1 ./deploy.sh"
		fi
	fi
}

preflight_buildkit_disk

DOCKERFILE="$ROOT_DIR/docker/Dockerfile"

build_rust_image() {
	local target="$1" bin_name="$2" image_tag="$3" image_latest="$4"
	printf '%s\n' "🔨 buildx $target ($bin_name)…" >&2

	# Inicializa ou verifica o builder remoto Hetzner automaticamente (padrão de alta performance)
	local USE_HETZNER=false
	local HETZNER_SETUP="$REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh"
	if [ -f "$HETZNER_SETUP" ]; then
		if "$HETZNER_SETUP" --silent; then
			USE_HETZNER=true
		fi
	fi

	if [ "$USE_HETZNER" = "true" ]; then
		echo "🚀 Usando builder Hetzner remoto de alta performance..."
		docker buildx build \
			--builder hetzner-builder \
			--platform linux/arm64 \
			--load \
			-f "$DOCKERFILE" \
			--target "$target" \
			--build-arg "BIN_NAME=$bin_name" \
			-t "$image_tag" \
			-t "$image_latest" \
			"$ROOT_DIR"
		
		echo "🔌 Garantindo túnel SSH para o registro local (porta 31444)..."
		if ! ss -tlnp 2>/dev/null | grep -q ':31444'; then
			ssh -o StrictHostKeyChecking=no -L 31444:localhost:31444 oci-k8s-master -N -f
			sleep 1
		fi

		local local_tag="${image_tag/registry.local:31444/localhost:31444}"
		local local_latest="${image_latest/registry.local:31444/localhost:31444}"
		docker tag "$image_tag" "$local_tag"
		docker tag "$image_latest" "$local_latest"

		echo "⬆️ Enviando imagem leve ao registro local..."
		docker push "$local_tag"
		docker push "$local_latest"
		docker rmi "$local_tag" "$local_latest" >/dev/null 2>&1 || true
	else
		echo "⚠️ Builder Hetzner inativo. Usando o oci-builder padrão..."
		docker buildx build \
			--builder oci-builder \
			--platform linux/arm64 \
			--push \
			-f "$DOCKERFILE" \
			--target "$target" \
			--build-arg "BIN_NAME=$bin_name" \
			-t "$image_tag" \
			-t "$image_latest" \
			"$ROOT_DIR"
	fi
}

# T-200: skip CLI image when only API/console changed (saves ~20–30 min on oci-builder).
should_deploy_cli() {
	case "${AI_RADAR_DEPLOY_CLI:-auto}" in
	0 | false | no | skip) return 1 ;;
	1 | true | yes) return 0 ;;
	auto)
		local base="${AI_RADAR_DIFF_BASE:-origin/main}"
		if ! git -C "$REPO_ROOT" rev-parse --verify "${base}^{commit}" >/dev/null 2>&1; then
			return 0
		fi
		if git -C "$REPO_ROOT" diff --name-only "${base}"...HEAD -- apps/ai-radar \
			| grep -qE 'apps/ai-radar/(crates/ai-radar-cli/|crates/ai-radar-core/|docker/|Cargo\.(toml|lock))'; then
			return 0
		fi
		return 1
		;;
	*)
		die "AI_RADAR_DEPLOY_CLI inválido: ${AI_RADAR_DEPLOY_CLI:-} (use auto|0|1)"
		;;
	esac
}

resolve_cli_image_for_manifest() {
	if should_deploy_cli; then
		build_rust_image runtime-cli ai-radar "$IMAGE_CLI_TAG" "$IMAGE_CLI_LATEST"
		printf '%s' "$IMAGE_CLI_TAG"
		return
	fi
	local current
	current="$(
		kubectl get cronjob ai-radar-extract -n ai-radar \
			-o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}' 2>/dev/null || true
	)"
	if [[ -n "$current" ]]; then
		printf '%s\n' "⏭️  CLI inalterado (AI_RADAR_DEPLOY_CLI=auto) — reutilizando $current" >&2
		printf '%s' "$current"
		return
	fi
	printf '%s\n' '⚠️  CronJob extract sem imagem — build CLI mesmo com auto' >&2
	build_rust_image runtime-cli ai-radar "$IMAGE_CLI_TAG" "$IMAGE_CLI_LATEST"
	printf '%s' "$IMAGE_CLI_TAG"
}

build_rust_image runtime-api ai-radar-api "$IMAGE_API_TAG" "$IMAGE_API_LATEST"
IMAGE_CLI_FOR_MANIFEST="$(resolve_cli_image_for_manifest)"

MANIFEST="$(mktemp)"
cleanup() {
	rm -f "$MANIFEST"
}
trap cleanup EXIT

kubectl kustomize "$ROOT_DIR/k8s/overlays/production" >"$MANIFEST"
sed -i "s|registry.local:31444/repository/docker-repo/my-site-ai-radar-api:[^[:space:]]*|${IMAGE_API_TAG}|g" "$MANIFEST"
sed -i "s|registry.local:31444/repository/docker-repo/my-site-ai-radar-cli:[^[:space:]]*|${IMAGE_CLI_FOR_MANIFEST}|g" "$MANIFEST"

kubectl apply -f "$MANIFEST"

# Pós-build: prune profilático do cache BuildKit para prevenir DiskPressure acumulado (T-196).
# Mantém ≤ 8 GiB de cache (--keep-storage) — sem --all para preservar layers reutilizáveis.
# Executa apenas quando o cache ultrapassar o limiar AI_RADAR_BUILDKIT_MAX_CACHE_GB (padrão: 10 GiB).
postbuild_buildkit_prune() {
	local host="${OCI_BUILDKIT_HOST:-oci-k8s-master}"
	local max_gb="${AI_RADAR_BUILDKIT_MAX_CACHE_GB:-10}"
	local keep_bytes=8589934592 # 8 GiB

	local buildkit_du buildkit_gb
	buildkit_du="$(ssh -o BatchMode=yes "$host" \
		'sudo du -sk /var/lib/buildkit 2>/dev/null | awk "{print \$1}"' 2>/dev/null || echo 0)"
	buildkit_gb=$((buildkit_du / 1024 / 1024))

	printf '%s\n' "🧹 pós-build buildkit ($host): cache ≈ ${buildkit_gb} GiB (limiar ${max_gb} GiB)"
	if [[ "$buildkit_gb" -gt "$max_gb" ]]; then
		printf '%s\n' "   cache > ${max_gb} GiB — pruning para ≤ 8 GiB…"
		ssh -o BatchMode=yes "$host" \
			"sudo buildctl --addr unix:///run/buildkit/buildkitd.sock prune --keep-storage=${keep_bytes}" \
			>/dev/null 2>&1 \
			&& printf '%s\n' "   ✓ prune concluído" \
			|| printf '%s\n' "   ⚠️  prune pós-build falhou (não-bloqueante)" >&2
	fi
}

postbuild_buildkit_prune || true
