#!/bin/sh
# OCI Deploy — my-site-back-end
# Pré-requisitos:
#   kubectl: export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
#   push:    localhost:31444 disponível (nativo no nó master; remoto: ssh -L 31444:localhost:31444 oci-k8s-master -N)

set -e

npm cache clean -f && rm -rf node_modules/ && NODE_TLS_REJECT_UNAUTHORIZED=0 npm i
npm run build

TAG_VERSION=$(date +%s)
PUSH_REGISTRY=localhost:31444
K8S_REGISTRY=registry.local:31444
REPO=repository/docker-repo
SERVICE=my-site-back-end

PUSH_TAG=$PUSH_REGISTRY/$REPO/$SERVICE:$TAG_VERSION
PUSH_LATEST=$PUSH_REGISTRY/$REPO/$SERVICE:latest
K8S_TAG=$K8S_REGISTRY/$REPO/$SERVICE:$TAG_VERSION

docker buildx build \
  --platform linux/arm64 \
  --load \
  -t $PUSH_TAG \
  -t $PUSH_LATEST \
  .

docker push $PUSH_TAG
docker push $PUSH_LATEST

sed -i "s|image: .*|image: $K8S_TAG|" ./k8s/my-site-back-end.yaml

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
kubectl apply -f ./k8s/my-site-back-end.yaml
