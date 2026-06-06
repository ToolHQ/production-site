#!/bin/sh
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$SCRIPT_DIR
REPO_ROOT=$(CDPATH= cd -- "$APP_DIR/../.." && pwd)

TAG_VERSION=$(date +%s)
REGISTRY=registry.local:31444
REPO=repository/docker-repo
SERVICE=agent-meter

IMAGE_TAG=$REGISTRY/$REPO/$SERVICE:$TAG_VERSION
IMAGE_LATEST=$REGISTRY/$REPO/$SERVICE:latest

cd "$REPO_ROOT"

# Inicializa ou verifica o builder remoto Hetzner (alta performance)
USE_HETZNER=false
HETZNER_SETUP="$REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh"
if [ -f "$HETZNER_SETUP" ]; then
  if "$HETZNER_SETUP" --silent; then
    USE_HETZNER=true
  fi
fi

# Hash do conteúdo de crates/ para invalidar cache BuildKit quando HTML/RS muda
BUILD_HASH=$(find "$APP_DIR/crates" -type f | sort | xargs md5sum 2>/dev/null | md5sum | cut -c1-12)

if [ "$USE_HETZNER" = "true" ]; then
  echo "usando hetzner-builder (alta performance) [hash=$BUILD_HASH]"
  docker buildx build \
    --builder hetzner-builder \
    --platform linux/arm64 \
    --build-arg BUILD_HASH="$BUILD_HASH" \
    --load \
    -t $IMAGE_TAG \
    -t $IMAGE_LATEST \
    -f "$APP_DIR/Dockerfile" \
    .

  echo "garantindo túnel SSH para registro local (porta 31444)..."
  if ! ss -tlnp 2>/dev/null | grep -q ':31444'; then
    ssh -o StrictHostKeyChecking=no -L 31444:localhost:31444 oci-k8s-master -N -f
    sleep 1
  fi

  LOCAL_TAG="localhost:31444/repository/docker-repo/${SERVICE}:${TAG_VERSION}"
  LOCAL_LATEST="localhost:31444/repository/docker-repo/${SERVICE}:latest"
  docker tag "$IMAGE_TAG" "$LOCAL_TAG"
  docker tag "$IMAGE_LATEST" "$LOCAL_LATEST"

  echo "enviando imagem ao registro local..."
  docker push "$LOCAL_TAG"
  docker push "$LOCAL_LATEST"
  docker rmi "$LOCAL_TAG" "$LOCAL_LATEST" >/dev/null 2>&1 || true
else
  echo "builder Hetzner inativo, usando oci-builder padrão... [hash=$BUILD_HASH]"
  docker buildx build \
    --builder oci-builder \
    --platform linux/arm64 \
    --build-arg BUILD_HASH="$BUILD_HASH" \
    --push \
    -t $IMAGE_TAG \
    -t $IMAGE_LATEST \
    -f "$APP_DIR/Dockerfile" \
    .
fi

render_and_apply() {
  local manifest="$1"
  local rendered
  rendered=$(mktemp)
  sed "s|image: IMAGE_PLACEHOLDER|image: $IMAGE_TAG|" "$manifest" > "$rendered"
  echo "  applying $manifest -> $IMAGE_TAG"
  kubectl apply -f "$rendered"
  rm -f "$rendered"
}

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
render_and_apply "$APP_DIR/k8s/agent-meter.yaml"
render_and_apply "$APP_DIR/k8s/mcp-wrapper.yaml"
