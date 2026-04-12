#!/bin/sh
# Template — OCI Deploy Script
# Copiar para o serviço, ajustar SERVICE e MANIFEST, e renomear para deploy.sh.
#
# Pré-requisitos:
#   kubectl: export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
#   push:    localhost:31444 disponível
#            → Nó master: disponível nativamente via NodePort 31444
#            → Máquina remota: ssh -L 31444:localhost:31444 oci-k8s-master -N

set -e

TAG_VERSION=$(date +%s)
PUSH_REGISTRY=localhost:31444          # NodePort Nexus — localhost sempre aceito como insecure
K8S_REGISTRY=registry.local:31444     # In-cluster hostname (/etc/hosts + containerd hosts.toml nos nós)
REPO=repository/docker-repo
SERVICE=NOME_DO_SERVICO                # ex: my-site-nginx, my-site-back-end, torproxy
MANIFEST=k8s/NOME_DO_SERVICO.yaml     # ex: k8s/my-site-nginx.yaml

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

sed -i "s|image: .*|image: $K8S_TAG|" ./$MANIFEST

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
kubectl apply -f ./$MANIFEST
