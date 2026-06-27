#!/usr/bin/env bash
# OCI Deploy — my-site-back-end
#
# Pré-requisitos:
#   source oci-k8s-cluster/scripts/setup-dev-deploy.sh
#   export KUBECONFIG=oci-k8s-cluster/kubeconfig_tunnel.yaml
#   apps/back-end/.npmrc (gitignored — Nexus auth)
#
# Pré-voo automático via deploy-preflight (DEPLOY_SKIP_PREFLIGHT=1 para pular).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TAG_VERSION="$(date +%s)"
REGISTRY='registry.local:31444'
REPO='repository/docker-repo'
SERVICE='my-site-back-end'

IMAGE_TAG="$REGISTRY/$REPO/$SERVICE:$TAG_VERSION"
IMAGE_LATEST="$REGISTRY/$REPO/$SERVICE:latest"

export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
export REPO_ROOT
export DEPLOY_NAMESPACE=default
export DEPLOY_NPMRC="$SCRIPT_DIR/.npmrc"
export DEPLOY_CLEANUP_EVICTED=1

die() {
	printf '%s\n' "$*" >&2
	exit 1
}

[[ -f "$DEPLOY_NPMRC" ]] || die "❌ $DEPLOY_NPMRC ausente. Crie com auth Nexus (ver apps/back-end/.npmrc.example ou credstore)."

# shellcheck source=/dev/null
source "$REPO_ROOT/oci-k8s-cluster/scripts/lib/deploy-buildx.sh"

deploy_select_buildx_builder

build_args=(
	--secret "id=npmrc,src=$DEPLOY_NPMRC"
)
if [[ "$USE_HETZNER" != "true" ]]; then
	build_args+=(--add-host=nexus.dnor.io:10.0.1.100)
fi

cd "$SCRIPT_DIR"
deploy_buildx_push_images "$SERVICE" "$IMAGE_TAG" "$IMAGE_LATEST" . "${build_args[@]}"

sed -i "s|image: .*|image: $IMAGE_TAG|" ./k8s/my-site-back-end.yaml
kubectl apply -f ./k8s/my-site-back-end.yaml
kubectl rollout status deploy/my-site-back-end-deployment -n default --timeout=180s
