#!/bin/sh
# OCI Deploy — torproxy
# Pré-requisitos:
#   oci-builder: ~/production-site/oci-k8s-cluster/scripts/setup-dev-deploy.sh
#   kubectl:     export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

TAG_VERSION=$(date +%s)
REGISTRY=registry.local:31444
REPO=repository/docker-repo
SERVICE=torproxy

IMAGE_TAG=$REGISTRY/$REPO/$SERVICE:$TAG_VERSION
IMAGE_LATEST=$REGISTRY/$REPO/$SERVICE:latest

# Inicializa ou verifica o builder remoto Hetzner automaticamente (padrão de alta performance)
USE_HETZNER=false
HETZNER_SETUP="$REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh"
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
    -t $IMAGE_TAG \
    -t $IMAGE_LATEST \
    .
  
  echo "🔌 Garantindo túnel SSH para o registro local (porta 31444)..."
  if ! ss -tlnp 2>/dev/null | grep -q ':31444'; then
    ssh -o StrictHostKeyChecking=no -L 31444:localhost:31444 oci-k8s-master -N -f
    sleep 1
  fi

  LOCAL_TAG="localhost:31444/repository/docker-repo/${SERVICE}:${TAG_VERSION}"
  LOCAL_LATEST="localhost:31444/repository/docker-repo/${SERVICE}:latest"
  docker tag "$IMAGE_TAG" "$LOCAL_TAG"
  docker tag "$IMAGE_LATEST" "$LOCAL_LATEST"

  echo "⬆️ Enviando imagem leve ao registro local..."
  docker push "$LOCAL_TAG"
  docker push "$LOCAL_LATEST"
  docker rmi "$LOCAL_TAG" "$LOCAL_LATEST" >/dev/null 2>&1 || true
else
  echo "⚠️ Builder Hetzner inativo. Usando o oci-builder padrão..."
  docker buildx build \
    --builder oci-builder \
    --platform linux/arm64 \
    --push \
    -t $IMAGE_TAG \
    -t $IMAGE_LATEST \
    .
fi

sed -i "s|image: .*|image: $IMAGE_TAG|" ./k8s/torproxy.yaml

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
kubectl apply -f ./k8s/torproxy.yaml
