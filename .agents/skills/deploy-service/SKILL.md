---
name: deploy-service
description: Padrão "Build & Apply" usando deploy.sh — OCI/Nexus (ARM64).
---

# Deployment Workflow — OCI

Todo serviço em `apps/<service>` possui um `deploy.sh` (nginx usa `publish.sh`).

## Pré-requisitos

```bash
# Executar UMA VEZ por sessão (configura oci-builder + tunnels + auth)
cd ~/production-site-cursor
source oci-k8s-cluster/scripts/setup-dev-deploy.sh
export KUBECONFIG=~/production-site-cursor/oci-k8s-cluster/kubeconfig_tunnel.yaml
```

## Pré-voo obrigatório (antes de build/push)

**Sempre** rodar antes de deploy em recovery ou entrega crítica:

```bash
bash scripts/harness/validate_deploy_readiness.sh --namespace default --cleanup-evicted
# Node com @dnorio:
bash scripts/harness/validate_deploy_readiness.sh --npmrc apps/back-end/.npmrc --hetzner
```

Biblioteca compartilhada (chamada automaticamente por `deploy-buildx.sh` salvo `DEPLOY_SKIP_PREFLIGHT=1`):

| Check | O que evita |
| ----- | ----------- |
| Nexus API + PVC % | 500/503 npm, `No space left on device` |
| Quota namespace | rollout bloqueado (`FailedCreate`) |
| DiskPressure | evictions em cascata |
| ImagePullBackOff | imagens ausentes no registry |
| npm ping + `NODE_OPTIONS=--use-openssl-ca` | `Exit handler never called` / E401 no Hetzner |
| `.npmrc` presente | build Node sem auth |

Pós-deploy stack dnor.io:

```bash
bash scripts/harness/validate_site_stack.sh
```

## Pré-voo (antes de build/push — evitar falha após 20+ min)

Sempre **medir e estimar** no nó do `buildkitd` (`oci-k8s-master`) **antes** de `docker buildx build`, principalmente Rust/C++ ou duas imagens seguidas.

| Serviço / tipo | Pico típico (BuildKit + link) | Mínimo livre em `/` recomendado |
| -------------- | ----------------------------- | ------------------------------- |
| Node/static leve | ~2–4 GiB | ≥ 8 GiB |
| **AI Radar** (Rust api + cli, ARM64) | ~8–12 GiB cache + ~6–10 GiB no link (`aws-lc-sys`) | **≥ 12 GiB** (com rootfs higienizado; **≥ 18 GiB** se cache BuildKit > 8 GiB sem prune) |
| Após falha `no space left on device` | — | `buildctl prune --all` no master; revalidar `df -h /` |

Checagem rápida manual:

```bash
ssh oci-k8s-master 'df -h /; sudo du -sh /var/lib/buildkit; sudo buildctl --addr unix:///run/buildkit/buildkitd.sock du | tail -3'
```

`apps/ai-radar/deploy.sh` roda pré-voo automático (`preflight_buildkit_disk`). Default **12 GiB** livres; com `AI_RADAR_BUILDKIT_PRUNE=1` tenta `buildctl prune --all` se cache BuildKit ≥ 3 GiB.

**Higiene master (T-193):** remover legado `/data/minio_legacy_backup.tar` (~11 GiB), cache rootless órfão em `~/.local/share/buildkit`, `/tmp/build-swap` se existir; `clean_node.sh --deep` no `oci-k8s-master` após migrações ou antes de builds Rust pesados.

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

> **Hetzner builder (padrão)**: `oci-k8s-cluster/scripts/lib/deploy-buildx.sh` — `--load` na Hetzner + `docker push localhost:31444`. **Nunca** `--add-host=nexus.dnor.io:10.0.1.100` no path Hetzner (IP interno OCI inacessível).
>
> **Node/npm no Docker**: `ENV NODE_OPTIONS=--use-openssl-ca`; montar `.npmrc` via `--secret id=npmrc`; remover `cafile=` do npmrc no Dockerfile. Master-only: `--add-host=nexus.dnor.io:10.0.1.100`.

> **IMPORTANTE**: `oci-builder` é um buildx remote driver apontando para o buildkitd do master.  
> Não é binfmt local — é execução nativa ARM64 no nó.

## Padrão Canônico (preferir lib compartilhada)

```bash
# apps/<service>/deploy.sh (bash)
source "$REPO_ROOT/oci-k8s-cluster/scripts/lib/deploy-buildx.sh"
deploy_select_buildx_builder
deploy_buildx_push_images "$SERVICE" "$IMAGE_TAG" "$IMAGE_LATEST" "$CONTEXT_DIR" -- [buildx extras]
kubectl apply -f ./k8s/<service>.yaml
```

Legado mínimo (evitar em apps novos):

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
