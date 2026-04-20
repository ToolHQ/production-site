# T-114 — OCI Deploy Pipeline: minikube → OCI/Nexus Migration

**Status**: ✅ Done  
**Priority**: 🔼 High  
**Epic**: DevOps  
**Estimate**: 4h  
**Created**: 2026-04-12

---

## Contexto

Auditoria disparada pela revisão do app `apps/nginx/`. Descoberta: **todos os 5 apps deployáveis ainda têm o workflow de deploy orientado ao minikube**. Nada foi portado para OCI.

### Apps afetados

| App                     | Script       | Manifesto                               |
| ----------------------- | ------------ | --------------------------------------- |
| `apps/nginx`            | `publish.sh` | `k8s/minikube/my-site-nginx.yaml`       |
| `apps/back-end`         | `deploy.sh`  | `k8s/minikube/my-site-back-end.yaml`    |
| `apps/py-back-end`      | `deploy.sh`  | `k8s/minikube/my-site-py-back-end.yaml` |
| `apps/rs-axum-back-end` | `deploy.sh`  | `k8s/minikube/my-site-rs-back-end.yaml` |
| `apps/tor`              | `deploy.sh`  | `k8s/minikube/torproxy.yaml`            |

### Problemas identificados

1. **Registry host errado**: todos os scripts usam `DOCKER_REGISTRY_HOST=docker-nexus.localhost` (minikube IP `192.168.49.2` via `--add-host`). Esse hostname não existe no OCI.
2. **`--add-host` flags minikube**: `--add-host=docker-nexus.localhost:192.168.49.2`, `nexus.localhost:192.168.49.2`, `minio.localhost:192.168.49.2` — específicos do minikube.
3. **Manifesto em `k8s/minikube/`**: caminho esperado no OCI é `k8s/<app>.yaml` (plano, sem subpasta).
4. **Image ref no manifesto**: usa `docker-nexus.localhost/repository/docker-repo/...` — esse hostname não resolve nos nós OCI sem configuração adicional.
5. **Skill doc desatualizada**: `.agents/skills/deploy-service/SKILL.md` ainda referencia `nexus.localhost`.

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

- [x] Reescrito `.agents/skills/deploy-service/SKILL.md` com padrão OCI + tabela de registries + regras

### 7. Validar nginx no cluster (pós-migração)

- [x] `docker buildx build --platform linux/arm64 --push ...` bem-sucedido
- [x] `kubectl rollout status deployment/my-site-nginx-deployment -n default` → OK
- [x] Verificar pod pull sem ImagePullBackOff
- [x] Testar Ingress `https://dnor.io`

---

## Notas Técnicas

- **Namespace dos apps**: todos os manifestos atuais usam `namespace: default` — verificar se isso é correto para OCI (não há namespace dedicado para apps ainda)
- **Senhas em plaintext**: `apps/back-end` tem DB passwords em plain env vars no manifesto — candidato para K8s Secrets (tarefa separada)
- **Ingress host**: manifesto atual usa `my-site.localhost` → host real no OCI é desconhecido (verificar Ingress atual do cluster)
- **`registry.local`**: resolvido via `/etc/hosts` nos nós como `127.0.0.1` + NodePort 31444 → funciona para pull do containerd, **não funciona diretamente do dev local sem tunnel**
- **Exceção atual do back-end**: `apps/back-end/deploy.sh` ainda mantém `--add-host=nexus.dnor.io:10.0.1.100`. Isso não é mais resíduo minikube; é um workaround OCI específico porque o hostname `nexus.dnor.io` hoje não resolve de dentro do cluster/pods. A resiliência dessa dependência fica como follow-up natural para T-105.

## Validação Final — 2026-04-19

- A migração OCI está consolidada no layout atual do repo: os 5 apps deployáveis usam `registry.local:31444`, `--platform linux/arm64` e manifestos OCI planos em `k8s/*.yaml`.
- Auditoria local confirmou os artefatos canônicos em produção: `apps/nginx/publish.sh`, `apps/back-end/deploy.sh`, `apps/py-back-end/deploy.sh`, `apps/rs-axum-back-end/deploy.sh` e `apps/tor/deploy.sh`, além dos manifestos OCI correspondentes em `k8s/`.
- Evidência live do pipeline nginx já existia nas tasks filhas posteriores e foi reconfirmada nesta sessão: `kubectl rollout status deployment/my-site-nginx-deployment -n default` retornou sucesso e o pod `my-site-nginx-deployment-5c4895579-hxs6l` estava `1/1 Running`, sem `ImagePullBackOff`.
- A reachability pública do Ingress foi revalidada com `curl -kI https://dnor.io`, que respondeu `HTTP/1.1 405 Method Not Allowed`; isso confirma que o host público e a borda HTTPS estão ativos, mesmo que `HEAD` não seja aceito pela aplicação.
- O preflight do builder remoto `oci-builder` também foi revalidado nesta sessão durante o fechamento da T-115: o buildx remote driver estava `running`, com suporte a `linux/arm64`, preservando o caminho padrão de build OCI usado por esta migração.
- O único desvio remanescente é o `--add-host=nexus.dnor.io:10.0.1.100` no deploy do back-end. O motivo foi verificado ao vivo: um pod `my-site-back-end` no cluster respondeu `wget: bad address 'nexus.dnor.io'`, então esse override hoje é workaround operacional do ambiente OCI, não sobra de minikube.
