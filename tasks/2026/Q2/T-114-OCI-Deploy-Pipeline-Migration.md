# T-114 — OCI Deploy Pipeline: minikube → OCI/Nexus Migration

**Status**: 📅 Backlog  
**Priority**: 🔼 High  
**Epic**: DevOps  
**Estimate**: 4h  
**Created**: 2026-04-12

---

## Contexto

Auditoria disparada pela revisão do app `apps/nginx/`. Descoberta: **todos os 5 apps deployáveis ainda têm o workflow de deploy orientado ao minikube**. Nada foi portado para OCI.

### Apps afetados

| App | Script | Manifesto |
|-----|--------|-----------|
| `apps/nginx` | `publish.sh` | `k8s/minikube/my-site-nginx.yaml` |
| `apps/back-end` | `deploy.sh` | `k8s/minikube/my-site-back-end.yaml` |
| `apps/py-back-end` | `deploy.sh` | `k8s/minikube/my-site-py-back-end.yaml` |
| `apps/rs-axum-back-end` | `deploy.sh` | `k8s/minikube/my-site-rs-back-end.yaml` |
| `apps/tor` | `deploy.sh` | `k8s/minikube/torproxy.yaml` |

### Problemas identificados

1. **Registry host errado**: todos os scripts usam `DOCKER_REGISTRY_HOST=docker-nexus.localhost` (minikube IP `192.168.49.2` via `--add-host`). Esse hostname não existe no OCI.
2. **`--add-host` flags minikube**: `--add-host=docker-nexus.localhost:192.168.49.2`, `nexus.localhost:192.168.49.2`, `minio.localhost:192.168.49.2` — específicos do minikube.
3. **Manifesto em `k8s/minikube/`**: caminho esperado no OCI é `k8s/<app>.yaml` (plano, sem subpasta).
4. **Image ref no manifesto**: usa `docker-nexus.localhost/repository/docker-repo/...` — esse hostname não resolve nos nós OCI sem configuração adicional.
5. **Skill doc desatualizada**: `.agent/skills/deploy-service/SKILL.md` ainda referencia `nexus.localhost`.

### Infraestrutura real do OCI

- **Registry interno (NodePort)**: `registry.local:31444` → mapeado para `127.0.0.1:31444` em todos os nós via `/etc/hosts` + `hosts.toml` containerd
- **Registry externo (Ingress)**: `docker-nexus.dnor.io` → porta 18444 (sem TLS no ingress atual)
- **regsecret**: usa `SERVER="registry.local:31444"` → para pull funcionar, image names nos manifestos devem usar `registry.local:31444/`
- **BuildKit**: instalado rootless nos nós OCI (via `install_buildkit.sh`) para builds remotos

---

## Tasks

### 1. Definir o padrão canônico de push/pull para OCI

- [ ] **Decisão**: como o dev local empurra imagens ao Nexus OCI?
  - **Opção A** (recomendada): SSH tunnel `ssh -L 31444:localhost:31444 oci-k8s-master -N` → push para `registry.local:31444/...` como HTTP inseguro (já configurado no containerd)
  - **Opção B**: push para `docker-nexus.dnor.io` (requer `--insecure-registry=docker-nexus.dnor.io` no docker daemon local ou TLS válido)
  - **Opção C**: SSH no master node + build remoto via BuildKit → push local `registry.local:31444/...` diretamente do nó
- [ ] Documentar a escolha no `deploy-service/SKILL.md`

### 2. Criar padrão OCI de `deploy.sh` (template)

- [ ] Criar `oci-k8s-cluster/scripts/templates/deploy-template.sh` com:
  ```sh
  #!/bin/sh
  TAG=$(date +%s)
  REGISTRY="registry.local:31444"        # OCI NodePort — tunnel: ssh -L 31444:localhost:31444 oci-k8s-master -N
  REPO="repository/docker-repo"
  IMAGE="$REGISTRY/$REPO/<service-name>"
  
  docker buildx build --platform linux/arm64 -t "$IMAGE:$TAG" -t "$IMAGE:latest" --push .
  
  sed -i "s|image: .*|image: $IMAGE:$TAG|" ./k8s/<service>.yaml
  kubectl apply -f ./k8s/<service>.yaml
  ```
- [ ] Confirmar que `--platform linux/arm64` é necessário (build em x86 dev machine → cluster ARM64)

### 3. Migrar `apps/nginx` (nginx — publish.sh + manifesto)

- [ ] Atualizar `apps/nginx/publish.sh`:
  - `DOCKER_REGISTRY_HOST=registry.local:31444` (ou equivalente OCI)
  - Remover todos os `--add-host` do minikube
  - Adicionar `--platform linux/arm64`
  - Atualizar `sed` para apontar para `./k8s/my-site-nginx.yaml`
  - `kubectl apply -f ./k8s/my-site-nginx.yaml`
- [ ] Criar `apps/nginx/k8s/my-site-nginx.yaml` a partir de `k8s/minikube/my-site-nginx.yaml`:
  - Namespace: `default` (apps ficam em `default`? definir padrão)
  - Image: `registry.local:31444/repository/docker-repo/my-site-nginx:latest` (placeholder — sed atualiza no deploy)
  - Remover `host: my-site.localhost` → host OCI correto (verificar ingress atual do cluster)
  - Manter `imagePullSecrets: regsecret`
- [ ] Manter `k8s/minikube/` como histórico (não deletar ainda)

### 4. Migrar `apps/back-end` (deploy.sh + manifesto)

- [ ] Mesmas alterações de publish.sh acima, adaptadas para `deploy.sh` do back-end
- [ ] Criar `apps/back-end/k8s/my-site-back-end.yaml` (OCI)
- [ ] Verificar variáveis de ambiente: `DB_DNORIO_POSTGRES_*` — senhas em plaintext no manifesto (risco de segurança → usar Secrets)

### 5. Migrar `apps/py-back-end`, `apps/rs-axum-back-end`, `apps/tor`

- [ ] Mesmas migrações para os 3 apps restantes

### 6. Atualizar a skill `deploy-service`

- [ ] Reescrever `.agent/skills/deploy-service/SKILL.md` com padrão OCI definido
- [ ] Incluir passo de tunnel SSH e flag ARM64

### 7. Validar nginx no cluster (pós-migração)

- [ ] `docker buildx build --platform linux/arm64 --push ...` bem-sucedido
- [ ] `kubectl rollout status deployment/my-site-nginx-deployment -n default` → OK
- [ ] Verificar que pod consegue fazer pull da imagem (`Events` sem ImagePullBackOff)
- [ ] Testar Ingress (`curl https://<host>` ou equivalente OCI)

---

## Notas Técnicas

- **Namespace dos apps**: todos os manifestos atuais usam `namespace: default` — verificar se isso é correto para OCI (não há namespace dedicado para apps ainda)
- **Senhas em plaintext**: `apps/back-end` tem DB passwords em plain env vars no manifesto — candidato para K8s Secrets (tarefa separada)
- **Ingress host**: manifesto atual usa `my-site.localhost` → host real no OCI é desconhecido (verificar Ingress atual do cluster)
- **`registry.local`**: resolvido via `/etc/hosts` nos nós como `127.0.0.1` + NodePort 31444 → funciona para pull do containerd, **não funciona diretamente do dev local sem tunnel**
