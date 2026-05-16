# T-191: AI Radar — Cluster Smoke + Demo Runbook (post T-169)

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 4h

## Context
Com o **Digest Generator (T-169)** e **Observabilidade (T-172)** já mergeados, precisamos fechar o ciclo **cluster-first**:

- Build/push das imagens (ARM64, Nexus) e `kubectl apply` do overlay produção via `apps/ai-radar/deploy.sh`.
- Smoke test orientado a operador para provar:
  - API está `Running` e estável (`/health`, `/metrics`).
  - Digest funciona ponta-a-ponta no cluster: `POST /digest/run` → `GET /digests/:id` (`Accept: text/markdown`).
  - CronJobs existentes no namespace `ai-radar` executam sem falha de infraestrutura (e logs têm `job_id`).
  - Runbook documentado para repetição (sem “conhecimento tribal”).

Esta task é propositalmente **operacional/documental**, para virar um “manual de demo” e também um check de regressão pós-merge.

## Execução no cluster (2026-05-15)

**Pré-requisito:** tunnel `kubectl` ativo (`connect-to-cluster`). Comandos executados com `KUBECONFIG=oci-k8s-cluster/kubeconfig_tunnel.yaml`.

| Check | Resultado |
| ----- | --------- |
| `kubectl get nodes` | 4 nós Ready (`k8s-master`, `k8s-node-*`) |
| `kubectl -n ai-radar get deploy,svc,pods,cronjobs` | `deploy/ai-radar-api` 1/1 **Running**; Service ClusterIP :8080; CronJobs `collect` / `extract` / `score` ativos; histórico de Jobs **Completed** |
| Ingress | `ai-radar.dnor.io` (nginx) presente |
| Port-forward + `GET /health` | **200** — `{"status":"ok","service":"ai-radar-api","version":"0.1.0"}` |
| `GET /metrics` | **200** mas corpo vazio na imagem em execução (ponteiro para **T-172** — métricas app vs Prometheus handler) |

**Digest / API nova superfície:** na imagem **atualmente deployada** (~12d), `POST /digest/run` devolve **404** (router antigo). Código no repo inclui `POST /digest/run` e `GET /digests*`.

**Tentativa de redeploy** (`source setup-dev-deploy.sh`, `AI_RADAR_FROM_CLUSTER_PG_SECRET=1 ./deploy.sh`): build remoto (`oci-builder`) falhou com:

`copy_file_range: no space left on device` sob `/var/lib/buildkit/...` no host do BuildKit.

**Ação de infra recomendada antes do próximo deploy:** libertar espaço no nó que aloja `buildkitd` (prune controlado de cache BuildKit / snapshots; não aplicar `docker system prune -a` cegamente em produção sem checklist).

## Tasks
- [x] Conectar no cluster via tunnel (`connect-to-cluster`) e validar `kubectl get nodes`
- [x] Preparar ambiente de deploy (`deploy-service`): `source oci-k8s-cluster/scripts/setup-dev-deploy.sh` — **corrigido** bug de sintaxe em `setup-dev-deploy.sh` (printf linha buildkit) que impedia o script terminar
- [ ] Rodar `apps/ai-radar/deploy.sh` até conclusão (bloqueado: disco cheio no BuildKit remoto; ver acima)
- [x] Verificar recursos do namespace `ai-radar`:
  - [x] `kubectl -n ai-radar get deploy,svc,pods,cronjobs`
  - [ ] `kubectl -n ai-radar describe deploy ai-radar-api` (resources/probes) — opcional, não bloqueante
- [x] Smoke API via port-forward:
  - [x] `GET /health` 200
  - [ ] `GET /metrics` contém `ai_radar_` e `ai_radar_pending_raw_items` — **não** na imagem corrente (corpo vazio); revalidar após redeploy + T-172
- [ ] Smoke digest no cluster:
  - [ ] `POST /digest/run` retorna `digest_id` — depende de imagem nova no cluster
  - [ ] `GET /digests` lista itens
  - [ ] `GET /digests/:id` com `Accept: text/markdown` retorna Markdown
- [ ] Smoke CronJobs:
  - [ ] `kubectl -n ai-radar create job --from=cronjob/ai-radar-collect ...` completa
  - [ ] logs incluem `event="job.completed"` e `job_id`
- [x] Documentar “Como testar no cluster” (esta secção + nota de bloqueio deploy)

## References

- `apps/ai-radar/deploy.sh`
- `apps/ai-radar/k8s/overlays/production/`
- `docs/AI-RADAR-DECISIONS.md`

## Validação
Checklist objetivo (cluster):

- `kubectl -n ai-radar get pods` sem `CrashLoopBackOff`
- `/health` 200
- `/metrics` retorna Prometheus text
- Digest gera e é recuperável como Markdown
