#!/bin/sh
# OCI Deploy — my-site-ai-radar-api (Kustomize overlay production).
# Pré-requisitos:
#   oci-builder: ~/production-site/oci-k8s-cluster/scripts/setup-dev-deploy.sh
#   kubectl:     export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
# regsecret neste namespace (uma vez por namespace):
#   ~/production-site/components/nexus/create_registry_secret.sh ai-radar
#
# DATABASE_URL: substituir o Secret placeholder (SealedSecrets/SOPS/etc.) antes
# do rollout em produção. O artefato no Git usa apenas marcadores REPLACE_*.

set -e

TAG_VERSION=$(date +%s)
REGISTRY=registry.local:31444
REPO=repository/docker-repo
SERVICE=my-site-ai-radar-api

IMAGE_TAG=$REGISTRY/$REPO/$SERVICE:$TAG_VERSION
IMAGE_LATEST=$REGISTRY/$REPO/$SERVICE:latest

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT_DIR"

docker buildx build \
  --builder oci-builder \
  --platform linux/arm64 \
  --push \
  -f docker/Dockerfile.api \
  -t "$IMAGE_TAG" \
  -t "$IMAGE_LATEST" \
  .

MANIFEST=$(mktemp)
trap 'rm -f "$MANIFEST"' EXIT INT HUP

kubectl kustomize k8s/overlays/production >"$MANIFEST"
sed -i "s|registry.local:31444/repository/docker-repo/my-site-ai-radar-api:[^[:space:]]*|${IMAGE_TAG}|g" "$MANIFEST"

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
kubectl apply -f "$MANIFEST"
