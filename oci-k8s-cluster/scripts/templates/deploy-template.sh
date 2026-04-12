#!/bin/sh
# Template — OCI Deploy Script
# Copiar para o serviço, ajustar SERVICE e MANIFEST, e renomear para deploy.sh.
#
# Pré-requisitos (executar UMA VEZ por sessão):
#   cd ~/production-site && source oci-k8s-cluster/scripts/setup-dev-deploy.sh
#   export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
#
# Build: oci-builder (buildx remote → buildkitd ARM64 no oci-k8s-master via socket SSH)
# Push:  registry.local:31444 (NodePort Nexus; buildkitd acessa via slirp4netns NAT)
#        NÃO usar localhost:31444 aqui — rootlesskit desabilita loopback do host

set -e

TAG_VERSION=$(date +%s)
REGISTRY=registry.local:31444         # registry usado pelo buildkitd E pelo k8s
REPO=repository/docker-repo
SERVICE=NOME_DO_SERVICO                # ex: my-site-nginx, my-site-back-end, torproxy
MANIFEST=k8s/NOME_DO_SERVICO.yaml     # ex: k8s/my-site-nginx.yaml

IMAGE_TAG=$REGISTRY/$REPO/$SERVICE:$TAG_VERSION
IMAGE_LATEST=$REGISTRY/$REPO/$SERVICE:latest

docker buildx build \
  --builder oci-builder \
  --platform linux/arm64 \
  --push \
  -t $IMAGE_TAG \
  -t $IMAGE_LATEST \
  .

sed -i "s|image: .*|image: $IMAGE_TAG|" ./$MANIFEST

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
kubectl apply -f ./$MANIFEST
