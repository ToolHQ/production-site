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
SERVICE='my-site-ai-radar-api'

IMAGE_TAG="$REGISTRY/$REPO/$SERVICE:$TAG_VERSION"
IMAGE_LATEST="$REGISTRY/$REPO/$SERVICE:latest"

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

docker buildx build \
	--builder oci-builder \
	--platform linux/arm64 \
	--push \
	-f docker/Dockerfile.api \
	-t "$IMAGE_TAG" \
	-t "$IMAGE_LATEST" \
	"$ROOT_DIR"

MANIFEST="$(mktemp)"
cleanup() {
	rm -f "$MANIFEST"
}
trap cleanup EXIT

kubectl kustomize "$ROOT_DIR/k8s/overlays/production" >"$MANIFEST"
sed -i "s|registry.local:31444/repository/docker-repo/my-site-ai-radar-api:[^[:space:]]*|${IMAGE_TAG}|g" "$MANIFEST"

kubectl apply -f "$MANIFEST"
