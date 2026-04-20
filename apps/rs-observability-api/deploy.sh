#!/bin/sh
# OCI Deploy — rs-observability-api

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$SCRIPT_DIR
REPO_ROOT=$(CDPATH= cd -- "$APP_DIR/../.." && pwd)
BUNDLE_DIR="$APP_DIR/reports-bundle"

cleanup() {
  rm -rf "$BUNDLE_DIR"
}

trap cleanup EXIT INT TERM

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"
cp -RL "$REPO_ROOT/reports/latest" "$BUNDLE_DIR/latest"
cp -RL "$REPO_ROOT/reports/latest-catalog" "$BUNDLE_DIR/latest-catalog"

TAG_VERSION=$(date +%s)
REGISTRY=registry.local:31444
REPO=repository/docker-repo
SERVICE=rs-observability-api

IMAGE_TAG=$REGISTRY/$REPO/$SERVICE:$TAG_VERSION
IMAGE_LATEST=$REGISTRY/$REPO/$SERVICE:latest

cd "$APP_DIR"

docker buildx build \
  --builder oci-builder \
  --platform linux/arm64 \
  --push \
  -t $IMAGE_TAG \
  -t $IMAGE_LATEST \
  .

sed -i "s|image: .*|image: $IMAGE_TAG|" ./k8s/rs-observability-api.yaml

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
kubectl apply -f ./k8s/rs-observability-api.yaml
