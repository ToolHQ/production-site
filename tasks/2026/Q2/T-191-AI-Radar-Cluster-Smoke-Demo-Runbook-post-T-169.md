# T-191: AI Radar — Cluster Smoke + Demo Runbook (post T-169)

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Com o **Digest Generator (T-169)** e **Observabilidade (T-172)** mergeados, fechamos o ciclo **cluster-first**:

- Build/push ARM64 (Nexus) + `kubectl apply` via `apps/ai-radar/deploy.sh`.
- Smoke operador: `/health`, `/metrics` com `ai_radar_*`, digest ponta-a-ponta, CronJob manual com `job_id`.
- Runbook abaixo para repetição (sem conhecimento tribal).

## Execução no cluster (2026-05-16 — conclusão)

**Pré-requisito:** tunnel `kubectl` (`connect-to-cluster`), `KUBECONFIG=oci-k8s-cluster/kubeconfig_tunnel.yaml`.

| Check | Resultado |
| ----- | --------- |
| Higiene disco master (**T-193**) | Removidos tar MinIO (~11 GiB), cache rootless, `build-swap`; prune BuildKit ~23 GiB |
| `deploy.sh` (tag `1778940768`) | **OK** — API + CLI push; rollout `deployment/ai-radar-api` **successfully rolled out** |
| Imagem em execução | `my-site-ai-radar-api:1778940768` |
| `GET https://ai-radar.dnor.io/health` | **200** — `{"status":"ok",...}` |
| `GET /metrics` | `ai_radar_pending_raw_items 0` (+ séries Prometheus) |
| `POST /digest/run` | **200** — `{"digest_id":"..."}` |
| `GET /digests` | Lista com itens JSON |
| `GET /digests/:id` + `Accept: text/markdown` | Markdown válido (`# AI Radar Digest — …`) |
| Job manual collect | `kubectl create job --from=cronjob/ai-radar-collect collect-smoke-*` → **Complete** |
| Logs do job | `event="job.started"`, `event="job.completed"`, `job_id` presente |

### Comandos de smoke (repetíveis)

```bash
source ~/production-site/oci-k8s-cluster/scripts/setup-dev-deploy.sh
export KUBECONFIG=~/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml

kubectl -n ai-radar get deploy,pods,cronjobs
kubectl -n ai-radar rollout status deploy/ai-radar-api

curl -fsS https://ai-radar.dnor.io/health
curl -fsS https://ai-radar.dnor.io/metrics | grep '^ai_radar_' | head

DIGEST_ID=$(curl -fsS -X POST https://ai-radar.dnor.io/digest/run \
  -H 'Content-Type: application/json' -d '{"period":"daily"}' | jq -r .digest_id)
curl -fsS "https://ai-radar.dnor.io/digests/${DIGEST_ID}" -H 'Accept: text/markdown' | head

JOB="collect-smoke-$(date +%s)"
kubectl -n ai-radar create job --from=cronjob/ai-radar-collect "$JOB"
kubectl -n ai-radar wait --for=condition=complete "job/$JOB" --timeout=600s
kubectl -n ai-radar logs "job/$JOB" | grep -E 'job_id|job\.completed'
```

## Histórico (bloqueios resolvidos)

- **2026-05-15:** imagem antiga (~12d) — `/metrics` vazio, `POST /digest/run` **404**; build falhou por disco no BuildKit.
- **2026-05-16 (manhã):** prune + redeploy; primeiro build API OK; CLI + apply na segunda execução (**exit 0**).

## Tasks

- [x] Conectar no cluster via tunnel e validar nós Ready
- [x] Preparar ambiente de deploy (`setup-dev-deploy.sh`)
- [x] Rodar `apps/ai-radar/deploy.sh` até conclusão (API + CLI + apply)
- [x] Verificar recursos do namespace `ai-radar`
- [x] Smoke API: `/health` 200, `/metrics` com `ai_radar_*`
- [x] Smoke digest: `POST /digest/run`, `GET /digests`, `GET /digests/:id` Markdown
- [x] Smoke CronJob: job manual collect **Complete**; logs com `job_id` e `job.completed`
- [x] Documentar runbook (esta página)

## References

- `apps/ai-radar/deploy.sh`
- `apps/ai-radar/k8s/overlays/production/`
- `docs/AI-RADAR-DECISIONS.md`
- **T-193** — higiene disco master (pré-requisito do redeploy)

## Validação

- [x] `kubectl -n ai-radar get pods` sem `CrashLoopBackOff`
- [x] `/health` 200
- [x] `/metrics` retorna Prometheus text com `ai_radar_*`
- [x] Digest gera e é recuperável como Markdown
