# AI Radar — Observabilidade (ops)

Camada **A** da Fase 16 (**T-176**): dashboards Prometheus/Grafana e queries para **Coroot**, complementando o [Operator Console](../README.md) (produto em `https://ai-radar.dnor.io/`).

**Runbook SLO (Fase 22):** [`RUNBOOK.md`](RUNBOOK.md) — rollouts, filas, quando ignorar ERROR transitório no Coroot.

## Scrape

O Service `ai-radar-api` já expõe anotações padrão:

| Anotação | Valor |
| -------- | ----- |
| `prometheus.io/scrape` | `true` |
| `prometheus.io/port` | `8080` |
| `prometheus.io/path` | `/metrics` |

No cluster atual, o Prometheus do namespace **`coroot`** descobre o target como `job="kubernetes-service-endpoints"`, `namespace="ai-radar"`, `service="ai-radar-api"`.

Smoke rápido (tunnel + `KUBECONFIG`):

```bash
kubectl -n coroot port-forward svc/coroot-prometheus-server 19090:80
curl -fsS 'http://127.0.0.1:19090/api/v1/query?query=ai_radar_pending_raw_items' | jq '.data.result[0].value[1]'
```

During rollouts, `/metrics` refreshes DB-backed gauges at most once per **60s** and serves **stale** values on transient DNS/pool errors (**T-263**). Coroot `metrics: embedding coverage failed` spikes during deploy are expected to drop sharply.

**Probes (T-264):** liveness `GET /health`; readiness/startup `GET /health/ready` (503 until Postgres `SELECT 1` succeeds). Rollout: old pod drains before new pod passes readiness — fewer scrapes/traffic on pods sem DNS/DB.

**Degradação (T-265):** `/stats` omite `embeddings` se só a query de cobertura falhar; falhas transitórias de pool → **503** + `Retry-After: 5` em rotas read-only (`/stats`, `/items`, `/sources`).

## Métricas `ai_radar_*`

| Métrica | Tipo | Labels | Significado |
| ------- | ---- | ------ | ----------- |
| `ai_radar_pending_raw_items` | gauge | — | Fila `raw_items.status=pending` (atualizado a cada `GET /metrics`) |
| `ai_radar_embeddings_pending` | gauge | — | Itens extraídos sem vetor para `EMBEDDING_MODEL` (**T-255**) |
| `ai_radar_embeddings_coverage_pct` | gauge | — | `%` elegíveis com vetor (0–100, atualizado no scrape) (**T-261**) |
| `ai_radar_collected_total` | counter | `source_type` | Inserts em collect |
| `ai_radar_skipped_total` | counter | `source_type` | Duplicatas ignoradas |
| `ai_radar_sources_skipped_poll_total` | counter | `source_type` | Fontes não polled (intervalo) |
| `ai_radar_entries_rejected_total` | counter | `source_type`, `reason` | Ex.: `oversize_body` |
| `ai_radar_extracted_total` | counter | — | Extract OK |
| `ai_radar_extract_failed_total` | counter | — | Extract → failed |
| `ai_radar_scored_total` | counter | — | Score OK |
| `ai_radar_score_failed_total` | counter | — | Score falhou |
| `ai_radar_errors_total` | counter | `stage` | `collect` / `extract` / `score` |
| `ai_radar_stage_duration_seconds` | histogram | `stage` | Duração wall-clock por estágio |

> Contadores só aparecem no `/metrics` **após** o primeiro incremento desde o boot do pod (comportamento normal do exporter). O gauge `pending` está sempre presente.

Implementação: `crates/ai-radar-core/src/metrics.rs`.

## Grafana

1. Abra Grafana (ou importe no Prometheus UI do Coroot se não houver Grafana dedicado).
2. **Dashboards → Import → Upload JSON**
3. Arquivo: [`grafana/ai-radar-pipeline.json`](grafana/ai-radar-pipeline.json)
4. Datasource: Prometheus do cluster (ex. `coroot-prometheus-server`).

## Coroot

No **Coroot** (`https://coroot.dnor.io`), use **Metrics** / explorador com as queries abaixo (ajuste o seletor de workload para `ai-radar` / `ai-radar-api` quando disponível).

| Painel sugerido | PromQL |
| --------------- | ------ |
| Fila extract | `ai_radar_pending_raw_items{namespace="ai-radar"}` |
| Collect / 5m | `sum(rate(ai_radar_collected_total{namespace="ai-radar"}[5m])) by (source_type)` |
| Erros / 5m | `sum(rate(ai_radar_errors_total{namespace="ai-radar"}[5m])) by (stage)` |
| Latência p95 collect | `histogram_quantile(0.95, sum(rate(ai_radar_stage_duration_seconds_bucket{namespace="ai-radar",stage="collect"}[5m])) by (le))` |
| Fila embed | `ai_radar_embeddings_pending{namespace="ai-radar"}` |
| Cobertura semântica | `ai_radar_embeddings_coverage_pct{namespace="ai-radar"}` |

## Alertas sugeridos (não aplicados automaticamente)

Exemplos para PrometheusRule ou UI Coroot — calibrar limiares após baseline:

```yaml
# Fila de extract alta por 2h
- alert: AiRadarPendingRawItemsHigh
  expr: ai_radar_pending_raw_items{namespace="ai-radar"} > 50
  for: 2h
  labels:
    severity: warning
  annotations:
    summary: "AI Radar: muitos raw_items pendentes de extract"

# Falhas de score
- alert: AiRadarScoreFailures
  expr: increase(ai_radar_score_failed_total{namespace="ai-radar"}[1h]) > 0
  for: 5m
  labels:
    severity: warning

# Collect com erros
- alert: AiRadarCollectErrors
  expr: increase(ai_radar_errors_total{namespace="ai-radar",stage="collect"}[30m]) > 3
  for: 10m
  labels:
    severity: warning

# Cobertura semântica baixa (T-261)
- alert: AiRadarEmbeddingsCoverageLow
  expr: ai_radar_embeddings_coverage_pct{namespace="ai-radar"} < 50
  for: 4h

# Fila de embed alta (T-261)
- alert: AiRadarEmbeddingsPendingHigh
  expr: ai_radar_embeddings_pending{namespace="ai-radar"} > 80
  for: 2h
```

Arquivo de referência: [`prometheus/alerting-rules.example.yaml`](prometheus/alerting-rules.example.yaml).

**PromQL smoke** (Coroot / Prometheus UI):

```bash
curl -fsS 'http://127.0.0.1:19090/api/v1/query?query=ai_radar_embeddings_coverage_pct{namespace="ai-radar"}' | jq .
curl -fsS 'http://127.0.0.1:19090/api/v1/query?query=ai_radar_embeddings_pending{namespace="ai-radar"}' | jq .
```

## Produto vs ops

| Superfície | URL / artefato | Público |
| ---------- | -------------- | ------- |
| Console (digest, fontes) | https://ai-radar.dnor.io/ | Stakeholder / operador |
| Métricas / dashboards | Prometheus Coroot + Grafana JSON | SRE |
