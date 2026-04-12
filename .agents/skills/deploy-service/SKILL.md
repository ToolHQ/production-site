---
name: deploy-service
description: Padrão "Build & Apply" usando deploy.sh — OCI/Nexus (ARM64).
---

# Deployment Workflow — OCI

Todo serviço em `apps/<service>` possui um `deploy.sh` (nginx usa `publish.sh`).

## Pré-requisitos

```bash
# 1. kubectl apontado para o cluster OCI
export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml

# 2. Registry Nexus acessível em localhost:31444
#    → No nó master: disponível nativamente (NodePort 31444)
#    → De máquina remota: ssh -L 31444:localhost:31444 oci-k8s-master -N
```

## Registries

| Uso                        | Host                   | Observação                                                                    |
| -------------------------- | ---------------------- | ----------------------------------------------------------------------------- |
| `docker push` (build time) | `localhost:31444`      | Sempre aceito como insecure pelo Docker                                       |
| K8s image ref (manifesto)  | `registry.local:31444` | Resolve para `127.0.0.1` nos nós via `/etc/hosts` + containerd `hosts.toml`   |
| Pull secret                | `regsecret`            | Configurado com `registry.local:31444`; apply via `create_registry_secret.sh` |

## Padrão Canônico

```sh
#!/bin/sh
set -e

TAG_VERSION=$(date +%s)
PUSH_REGISTRY=localhost:31444         # push via NodePort (nativo no master)
K8S_REGISTRY=registry.local:31444    # pull in-cluster
REPO=repository/docker-repo
SERVICE=my-site-<nome>

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

sed -i "s|image: .*|image: $K8S_TAG|" ./k8s/<service>.yaml

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
kubectl apply -f ./k8s/<service>.yaml
```

## Manifesto K8s (estrutura)

```
apps/<service>/
├── deploy.sh          ← script de deploy OCI
├── k8s/
│   ├── <service>.yaml ← manifesto OCI (sem subpasta)
│   └── minikube/      ← legado minikube (não usar)
└── Dockerfile
```

## Regras

1. Sempre use `./deploy.sh` (ou `./publish.sh` para nginx) na raiz do serviço.
2. **Não comite** o YAML após o `sed` (tem tag numérica no `image:`). Verifique com `git diff` antes de commitar.
3. O manifesto OCI fica em `k8s/<service>.yaml` — **não** em `k8s/minikube/`.
4. `--platform linux/arm64` obrigatório: cluster é Oracle Ampere ARM64.
5. `imagePullPolicy: Always` nos manifestos garante que novos tags sejam puxados.
