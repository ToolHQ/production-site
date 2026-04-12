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

- [x] **Decisão**: **Opção A escolhida** — `localhost:31444` via NodePort (nativo no nó master; SSH tunnel `-L 31444` para dev remoto)
- [x] Documentar a escolha no `deploy-service/SKILL.md`

### 2. Criar padrão OCI de `deploy.sh` (template)

- [x] Criar `oci-k8s-cluster/scripts/templates/deploy-template.sh` com padrão canônico
- [x] Confirmado: `--platform linux/arm64` obrigatório (OCI Ampere ARM64)

### 3. Migrar `apps/nginx` (nginx — publish.sh + manifesto)

- [x] Atualizar `apps/nginx/publish.sh` → OCI (registry.local, sem --add-host, com --platform linux/arm64)
- [x] Criar `apps/nginx/k8s/my-site-nginx.yaml` — ingress host `dnor.io`, image `registry.local:31444`
- [x] Manter `k8s/minikube/` como histórico

### 4. Migrar `apps/back-end` (deploy.sh + manifesto)

- [x] Atualizar `apps/back-end/deploy.sh` → OCI
- [x] Criar `apps/back-end/k8s/my-site-back-end.yaml` (OCI)
- [ ] ⚠️ DB passwords em plaintext no manifesto → migrar para K8s Secrets (tarefa separada)

### 5. Migrar `apps/py-back-end`, `apps/rs-axum-back-end`, `apps/tor`

- [x] `apps/py-back-end/deploy.sh` + `k8s/my-site-py-back-end.yaml` (OCI; `MINIO_ENDPOINT` → `minio-service.minio.svc.cluster.local`)
- [x] `apps/rs-axum-back-end/deploy.sh` + `k8s/my-site-rs-back-end.yaml` (OCI)
- [x] `apps/tor/deploy.sh` + `k8s/torproxy.yaml` (OCI)

### 6. Atualizar a skill `deploy-service`

- [x] Reescrito `.agent/skills/deploy-service/SKILL.md` com padrão OCI + tabela de registries + regras

### 7. Validar nginx no cluster (pós-migração)

- [ ] `docker buildx build --platform linux/arm64 --push ...` bem-sucedido
- [ ] `kubectl rollout status deployment/my-site-nginx-deployment -n default` → OK
- [ ] Verificar pod pull sem ImagePullBackOff
- [ ] Testar Ingress `https://dnor.io`

---

## Notas Técnicas

- **Namespace dos apps**: todos os manifestos atuais usam `namespace: default` — verificar se isso é correto para OCI (não há namespace dedicado para apps ainda)
- **Senhas em plaintext**: `apps/back-end` tem DB passwords em plain env vars no manifesto — candidato para K8s Secrets (tarefa separada)
- **Ingress host**: manifesto atual usa `my-site.localhost` → host real no OCI é desconhecido (verificar Ingress atual do cluster)
- **`registry.local`**: resolvido via `/etc/hosts` nos nós como `127.0.0.1` + NodePort 31444 → funciona para pull do containerd, **não funciona diretamente do dev local sem tunnel**
