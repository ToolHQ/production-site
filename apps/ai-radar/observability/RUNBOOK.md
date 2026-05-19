# AI Radar — Pipeline SLO & Runbook (T-266)

Operação do pipeline **collect → extract → score → embed** e da API `ai-radar-api` no cluster OCI.

**Console:** https://ai-radar.dnor.io/ · **Coroot:** https://coroot.dnor.io · **Métricas:** [`README.md`](README.md)

---

## SLOs operacionais (baseline Q2 2026)

Valores alvo para operação saudável. Calibrar após 2 semanas de baseline se necessário.

| Sinal | Alvo | Onde medir | Alerta exemplo |
| ----- | ---- | ---------- | -------------- |
| Fila extract | `raw_items_pending` **≤ 50** fora de janela de extract | `/stats`, gauge `ai_radar_pending_raw_items` | > 50 por **2h** |
| Cobertura semântica | **`≥ 80%`** (`embeddings_coverage_pct`) | `/stats`, gauge `ai_radar_embeddings_coverage_pct` | < 50% por **4h** |
| Fila embed | `embeddings_pending` tendendo a **0**; aceitável **≤ 80** em steady state | `/stats`, gauge `ai_radar_embeddings_pending` | > 80 por **2h** |
| Latência p95 collect | **< 120s** por pass (CronJob) | `ai_radar_stage_duration_seconds{stage="collect"}` | investigar se > 300s |
| Latência p95 extract | **< 600s** por pass | histogram `stage="extract"` | job `activeDeadlineSeconds=900` |
| Latência p95 embed | **< 120s** (lote 50–100) | histogram `stage="embed"` | catch-up manual se fila alta |
| Erros collect | **0** sustained; spike **≤ 3**/30min | `ai_radar_errors_total{stage="collect"}` | alerta T-176 |
| Score failures | **0**/h em steady state | `ai_radar_score_failed_total` | alerta T-176 |
| API availability | `/health` 200; `/health/ready` 200 quando Ready | probes K8s | NotReady > 5min |

**Meta Fase 21 (atingida):** cobertura semântica ~**91%**. Manter **≥ 80%** após novos collects.

---

## CronJobs (namespace `ai-radar`)

| CronJob | Schedule | Comando | Notas |
| ------- | -------- | ------- | ----- |
| `ai-radar-collect` | `*/30 * * * *` | `collect` | RSS/GitHub → `raw_items` |
| `ai-radar-extract` | `15,45 * * * *` | `extract --limit 15` | + embed tail pós-pass (**T-259**) |
| `ai-radar-score` | `5 * * * *` | `score` | Regras + LLM opcional |
| `ai-radar-embed` | `25,55 * * * *` | `embed` | Lote `EMBED_BATCH_LIMIT` (50) |
| `ai-radar-embed-catchup` | `15 */4 * * *` | `embed` | Lote 100 (**T-260**) |

Ordem típica por hora: collect (:00/:30) → score (:05) → extract (:15/:45) → embed (:25/:55) → catch-up (:15 a cada 4h).

---

## Checagens rápidas (smoke)

```bash
export API=https://ai-radar.dnor.io
export KUBECONFIG=~/production-site-cursor/oci-k8s-cluster/kubeconfig_tunnel.yaml

curl -fsS "$API/health" | jq .
curl -fsS "$API/health/ready" | jq .
curl -fsS "$API/stats" | jq .

kubectl get cronjob,deploy -n ai-radar
kubectl get pods -n ai-radar -l app.kubernetes.io/name=ai-radar-api
kubectl logs -n ai-radar deployment/ai-radar-api --tail=30 | grep -E 'WARN|ERROR' || true
```

---

## Playbook: deploy / rollout da API

Fase 22 (**T-263–265**) reduz ruído durante troca de pods.

1. **Antes:** `kubectl get pods -n ai-radar` — anotar cobertura em `/stats`.
2. **Deploy:** `cd apps/ai-radar && AI_RADAR_DEPLOY_CLI=0 ./deploy.sh` (ou só API se CLI inalterado).
3. **Durante rollout:**
   - Pod novo fica **NotReady** até `GET /health/ready` (`SELECT 1`) passar (**T-264**).
   - Coroot pode mostrar poucos `WARN metrics: transient DB error` ou `metrics.gauge_stale` — **esperado** se < 2 min.
   - **Ignorar** rajadas de `ERROR metrics: embedding coverage failed` **só durante rollout** (< 5 min) se `/stats` e `/health/ready` voltam OK.
4. **Sinal de problema real:** NotReady > **5 min**, `/health/ready` 503 contínuo, ou `/stats` 503 fora de rollout.
5. **Depois:** confirmar gauges em `/metrics` (`embeddings_coverage_pct`, `embeddings_pending`).

---

## Playbook: fila embed alta

Sintoma: `embeddings_pending` > 80 ou cobertura < 80%.

```bash
curl -fsS "$API/stats" | jq '.embeddings'

# Job manual catch-up (lote 100)
kubectl create job "embed-backfill-$(date +%s)" \
  --from=cronjob/ai-radar-embed-catchup -n ai-radar
kubectl wait --for=condition=complete -n ai-radar job/<nome> --timeout=1200s
kubectl logs -n ai-radar job/<nome> --tail=20 | grep embed.coverage
```

Repetir até `embeddings_pending` aceitável. Ver também README § Embedding backfill.

---

## Playbook: fila extract alta

Sintoma: `raw_items_pending` > 50 por > 2h.

1. Verificar secret `ai-radar-llm` (`LLM_ENABLED`, API key).
2. Logs: `kubectl logs -n ai-radar -l job-name --tail=50` (último job extract).
3. Job manual: `kubectl create job extract-manual-$(date +%s) --from=cronjob/ai-radar-extract -n ai-radar`
4. Se falhas LLM (429/timeout): revisar `LLM_MAX_RPM` no ConfigMap.

---

## Playbook: Coroot ERROR vs incidente

| Log / alerta | Rollout? | Ação |
| ------------ | -------- | ---- |
| `metrics: transient DB error` | Sim | Monitorar; stale gauges OK (**T-263**) |
| `metrics.gauge_stale` | Sim | Normal se < 2 min |
| `readiness: database ping failed` | Sim (início pod) | OK se pod fica Ready em < 2 min |
| `readiness: database ping failed` | Não, > 5 min | Postgres/DNS — verificar `postgres` namespace |
| `metrics: embedding coverage failed` | Sim, < 5 min | Ignorar se `/stats` OK após rollout |
| `metrics: embedding coverage failed` | Não, contínuo | Pool/Postgres; checar conexões API |
| `503 service_unavailable` em `/stats` | Qualquer | Retry; se persistente → DB (**T-265**) |
| `/stats` 200 sem bloco `embeddings` | Qualquer | Degradação parcial — KPIs base OK (**T-265**) |

---

## Playbook: API degradada (503)

Rotas read-only retornam **503** + `Retry-After: 5` em falha transitória de pool (**T-265**).

1. `curl -i "$API/stats"` — header `Retry-After`.
2. `curl -fsS "$API/health/ready"` — se 503, Postgres indisponível.
3. Console home pode carregar parcialmente se só embeddings falharem.
4. Escalar: verificar Postgres (`kubectl get pods -n postgres`), pool API, DNS cluster.

---

## Referências

| Artefato | Path |
| -------- | ---- |
| Alertas exemplo | [`prometheus/alerting-rules.example.yaml`](prometheus/alerting-rules.example.yaml) |
| Dashboard Grafana | [`grafana/ai-radar-pipeline.json`](grafana/ai-radar-pipeline.json) |
| Deploy | [`../deploy.sh`](../deploy.sh), [`../README.md`](../README.md) |
| Roadmap Fase 22–23 | [`../../../docs/AI-RADAR-ROADMAP.md`](../../../docs/AI-RADAR-ROADMAP.md) |
