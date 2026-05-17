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

docker buildx build \
  --builder oci-builder \
  --platform linux/arm64 \
  --push \
  -t $IMAGE_TAG \
  -t $IMAGE_LATEST \
  -f "$APP_DIR/Dockerfile" \
  .

RENDERED_MANIFEST=$(mktemp)
sed "s|image: .*|image: $IMAGE_TAG|" "$APP_DIR/k8s/agent-meter.yaml" > "$RENDERED_MANIFEST"

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
kubectl apply -f "$RENDERED_MANIFEST"
rm -f "$RENDERED_MANIFEST"
