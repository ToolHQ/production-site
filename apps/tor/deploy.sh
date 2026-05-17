#!/bin/sh
# OCI Deploy — torproxy
# Pré-requisitos:
#   oci-builder: ~/production-site/oci-k8s-cluster/scripts/setup-dev-deploy.sh
#   kubectl:     export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml

set -e

TAG_VERSION=$(date +%s)
REGISTRY=registry.local:31444
REPO=repository/docker-repo
SERVICE=torproxy

IMAGE_TAG=$REGISTRY/$REPO/$SERVICE:$TAG_VERSION
IMAGE_LATEST=$REGISTRY/$REPO/$SERVICE:latest

USE_HETZNER=false
if docker buildx inspect hetzner-builder >/dev/null 2>&1; then
  if docker buildx inspect hetzner-builder 2>/dev/null | grep -q 'Status:.*running'; then
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
  echo "⬆️ Enviando imagem leve ao registro local..."
  docker push $IMAGE_TAG
  docker push $IMAGE_LATEST
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
