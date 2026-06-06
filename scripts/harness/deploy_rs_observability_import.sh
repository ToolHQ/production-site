#!/bin/sh
# Fallback quando Nexus docker registry não serve manifests (ImagePullBackOff).
# Uso: deploy_rs_observability_import.sh <tag> [ssh-host]
set -eu

TAG="${1:?usage: deploy_rs_observability_import.sh TAG [node-host]}"
NODE_HOST="${2:-oci-k8s-node-1}"
SERVICE=rs-observability-api
IMAGE="registry.local:31444/repository/docker-repo/${SERVICE}:${TAG}"
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
APP_DIR="$REPO_ROOT/apps/rs-observability-api"
TAR="/tmp/rs-api-${TAG}.tar"

export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml}"

if ! kubectl get deployment rs-observability-api-deployment -n default >/dev/null 2>&1; then
  exit 0
fi

PULL_STATE=$(kubectl get pods -n default -l app=rs-observability-api \
  -o jsonpath='{range .items[*]}{.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' 2>/dev/null \
  | grep -E 'ImagePullBackOff|ErrImagePull' || true)

if [ -z "$PULL_STATE" ]; then
  if kubectl rollout status deployment/rs-observability-api-deployment -n default --timeout=30s >/dev/null 2>&1; then
    exit 0
  fi
fi

echo "⚠️  ImagePullBackOff detectado — importando ${IMAGE} via ctr em ${NODE_HOST}..."

BUNDLE_DIR="$APP_DIR/reports-bundle"
mkdir -p "$BUNDLE_DIR"
cp -RL "$REPO_ROOT/reports/latest" "$BUNDLE_DIR/latest"
cp -RL "$REPO_ROOT/reports/latest-catalog" "$BUNDLE_DIR/latest-catalog"

cd "$APP_DIR"
docker buildx build \
  --builder hetzner-builder \
  --platform linux/arm64 \
  -t "$IMAGE" \
  --output "type=docker,dest=${TAR}" \
  .

scp -o StrictHostKeyChecking=no "$TAR" "${NODE_HOST}:${TAR}"
ssh -o StrictHostKeyChecking=no "$NODE_HOST" "sudo ctr -n k8s.io images import ${TAR} && rm -f ${TAR}"
rm -f "$TAR"

kubectl delete pod -n default -l app=rs-observability-api \
  --field-selector=status.phase!=Running --force --grace-period=0 >/dev/null 2>&1 || true
kubectl rollout status deployment/rs-observability-api-deployment -n default --timeout=120s
echo "✅ Import concluído para ${IMAGE}"
