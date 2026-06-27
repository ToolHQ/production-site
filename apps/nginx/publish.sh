#!/usr/bin/env bash
# OCI Deploy — my-site-nginx (frontend reverse proxy)
#
# Padrão Hetzner + push via túnel localhost:31444 (nunca oci-builder --push direto).
#
# Pré-requisitos:
#   source oci-k8s-cluster/scripts/setup-dev-deploy.sh
#   export KUBECONFIG=oci-k8s-cluster/kubeconfig_tunnel.yaml
#   GeoLite2 *.mmdb + GeoIP.conf no diretório (gitignored)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TAG_VERSION="$(date +%s)"
REGISTRY='registry.local:31444'
REPO='repository/docker-repo'
SERVICE='my-site-nginx'

IMAGE_TAG="$REGISTRY/$REPO/$SERVICE:$TAG_VERSION"
IMAGE_LATEST="$REGISTRY/$REPO/$SERVICE:latest"

export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
export REPO_ROOT
export DEPLOY_NAMESPACE=default
export DEPLOY_CLEANUP_EVICTED=1

for f in GeoIP.conf; do
	[[ -f "$SCRIPT_DIR/$f" ]] || {
		echo "❌ $SCRIPT_DIR/$f ausente (copie de ~/production-site/apps/nginx/)" >&2
		exit 1
	}
done

# shellcheck source=/dev/null
source "$REPO_ROOT/oci-k8s-cluster/scripts/lib/deploy-buildx.sh"

deploy_select_buildx_builder

cd "$SCRIPT_DIR"
deploy_buildx_push_images "$SERVICE" "$IMAGE_TAG" "$IMAGE_LATEST" .

sed -i "s|image: .*|image: $IMAGE_TAG|" ./k8s/my-site-nginx.yaml
kubectl apply -f ./k8s/my-site-nginx.yaml
kubectl rollout status deploy/my-site-nginx-deployment -n default --timeout=300s
