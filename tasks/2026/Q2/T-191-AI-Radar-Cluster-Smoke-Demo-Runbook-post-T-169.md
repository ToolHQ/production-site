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

Referências:
- `apps/ai-radar/deploy.sh`
- `apps/ai-radar/k8s/overlays/production/`
- `docs/AI-RADAR-DECISIONS.md`

## Tasks
- [ ] Conectar no cluster via tunnel (`connect-to-cluster`) e validar `kubectl get nodes`
- [ ] Preparar ambiente de deploy (`deploy-service`): `source oci-k8s-cluster/scripts/setup-dev-deploy.sh`
- [ ] Rodar `apps/ai-radar/deploy.sh` (API + CLI, registry secret, kustomize apply)
- [ ] Verificar recursos do namespace `ai-radar`:
  - [ ] `kubectl -n ai-radar get deploy,svc,pods,cronjobs`
  - [ ] `kubectl -n ai-radar describe deploy ai-radar-api` (resources/probes)
- [ ] Smoke API via port-forward:
  - [ ] `GET /health` 200
  - [ ] `GET /metrics` contém `ai_radar_` e `ai_radar_pending_raw_items`
- [ ] Smoke digest no cluster:
  - [ ] `POST /digest/run` retorna `digest_id`
  - [ ] `GET /digests` lista itens
  - [ ] `GET /digests/:id` com `Accept: text/markdown` retorna Markdown
- [ ] Smoke CronJobs:
  - [ ] `kubectl -n ai-radar create job --from=cronjob/ai-radar-collect ...` completa
  - [ ] logs incluem `event="job.completed"` e `job_id`
- [ ] Documentar “Como testar no cluster” (comandos reais e outputs esperados) nesta task

## Validação
Checklist objetivo (cluster):

- `kubectl -n ai-radar get pods` sem `CrashLoopBackOff`
- `/health` 200
- `/metrics` retorna Prometheus text
- Digest gera e é recuperável como Markdown
