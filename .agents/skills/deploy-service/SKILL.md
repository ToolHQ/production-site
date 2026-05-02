---
name: deploy-service
description: Padrão "Build & Apply" usando deploy.sh — OCI/Nexus (ARM64).
---

# Deployment Workflow — OCI

Todo serviço em `apps/<service>` possui um `deploy.sh` (nginx usa `publish.sh`).

## Pré-requisitos

```bash
# Executar UMA VEZ por sessão (configura oci-builder + tunnels + auth)
cd ~/production-site
source oci-k8s-cluster/scripts/setup-dev-deploy.sh
export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml
```

## Arquitetura de Build/Push

```
dev local ──(SSH socket fwd)──► buildkitd ARM64 (oci-k8s-master)
  docker buildx                 /home/ubuntu/.local/share/buildkit/buildkitd.sock
  --builder oci-builder              │
  --push                             └──push──► registry.local:31444 (NodePort Nexus)
                                                    │
                                               k8s imagePull
```

## Registries

| Uso                           | Host                   | Observação                                                                    |
| ----------------------------- | ---------------------- | ----------------------------------------------------------------------------- |
| `--push` do buildkitd         | `registry.local:31444` | buildkitd usa slirp4netns NAT → localhost:31444 não funciona (rootlesskit --disable-host-loopback) |
| K8s image ref (manifesto)     | `registry.local:31444` | Resolve para `127.0.0.1` nos nós via `/etc/hosts` + containerd `hosts.toml`   |
| `docker login` local          | `localhost:31444`      | Via tunnel SSH `-L 31444:localhost:31444 oci-k8s-master`                      |
| Pull secret                   | `regsecret`            | **`create_registry_secret.sh <namespace> \| kubectl apply -f -`** imprime só YAML; aplique assim no namespace (**deve existir**): `~/production-site/components/nexus/create_registry_secret.sh`. |

> **IMPORTANTE**: `oci-builder` é um buildx remote driver apontando para o buildkitd do master.  
> Não é binfmt local — é execução nativa ARM64 no nó.

## Padrão Canônico

```sh
#!/bin/sh
set -e

TAG_VERSION=$(date +%s)
REGISTRY=registry.local:31444    # único registry: buildkitd push + k8s pull
REPO=repository/docker-repo
SERVICE=my-site-<nome>

IMAGE_TAG=$REGISTRY/$REPO/$SERVICE:$TAG_VERSION
IMAGE_LATEST=$REGISTRY/$REPO/$SERVICE:latest

docker buildx build \
  --builder oci-builder \
  --platform linux/arm64 \
  --push \
  -t $IMAGE_TAG \
  -t $IMAGE_LATEST \
  .

sed -i "s|image: .*|image: $IMAGE_TAG|" ./k8s/<service>.yaml

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
