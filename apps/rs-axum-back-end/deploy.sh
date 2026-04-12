#!/bin/sh
# OCI Deploy — my-site-rs-back-end
# Pré-requisitos:
#   oci-builder: ~/production-site/oci-k8s-cluster/scripts/setup-dev-deploy.sh
#   kubectl:     export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml

set -e

TAG_VERSION=$(date +%s)
REGISTRY=registry.local:31444
REPO=repository/docker-repo
SERVICE=my-site-rs-back-end

IMAGE_TAG=$REGISTRY/$REPO/$SERVICE:$TAG_VERSION
IMAGE_LATEST=$REGISTRY/$REPO/$SERVICE:latest

docker buildx build \
  --builder oci-builder \
  --platform linux/arm64 \
  --push \
  -t $IMAGE_TAG \
  -t $IMAGE_LATEST \
  .

sed -i "s|image: .*|image: $IMAGE_TAG|" ./k8s/my-site-rs-back-end.yaml

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
kubectl apply -f ./k8s/my-site-rs-back-end.yaml
