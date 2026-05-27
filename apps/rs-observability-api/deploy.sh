#!/bin/sh
# OCI Deploy — rs-observability-api

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR=$SCRIPT_DIR
REPO_ROOT=$(CDPATH= cd -- "$APP_DIR/../.." && pwd)
BUNDLE_DIR="$APP_DIR/reports-bundle"
MANIFEST_PATH="$APP_DIR/k8s/rs-observability-api.yaml"
RENDERED_MANIFEST=""

GENERATOR="$REPO_ROOT/scripts/aws-fleet/generate_fleet_artifacts.py"
if [ -f "$GENERATOR" ] && [ -f "$REPO_ROOT/config/external-fleet/registry.yaml" ]; then
  echo "🔄 Regenerando external fleet artifacts..."
  python3 "$GENERATOR" \
    --registry "$REPO_ROOT/config/external-fleet/registry.yaml" \
    --repo-root "$REPO_ROOT"
fi

cleanup() {
  rm -rf "$BUNDLE_DIR"
  if [ -n "$RENDERED_MANIFEST" ] && [ -f "$RENDERED_MANIFEST" ]; then
    rm -f "$RENDERED_MANIFEST"
  fi
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

# oci-builder --push é o padrão (Nexus pull instável com docker push via tunnel Hetzner).
# Opt-in explícito: USE_HETZNER=1 ./deploy.sh
USE_HETZNER=false
HETZNER_SETUP="$REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh"
if [ "${USE_HETZNER:-0}" = "1" ] && [ -f "$HETZNER_SETUP" ]; then
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

RENDERED_MANIFEST=$(mktemp)
sed "s|image: .*|image: $IMAGE_TAG|" "$MANIFEST_PATH" > "$RENDERED_MANIFEST"

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
kubectl apply -f "$RENDERED_MANIFEST"

IMPORT_SCRIPT="$REPO_ROOT/scripts/harness/deploy_rs_observability_import.sh"
if [ -x "$IMPORT_SCRIPT" ]; then
  "$IMPORT_SCRIPT" "$TAG_VERSION" || true
fi

kubectl rollout status deployment/rs-observability-api-deployment -n default --timeout=180s
