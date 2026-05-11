# T-172: AI Radar — Observabilidade

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp / Observability
- **Estimation**: 4h
- **Opened**: 2026-05-01

## Context

Logs JSON estruturados com `request_id` (API) e `job_id` (CronJobs) propagados em todos os spans. Métricas Prometheus em `/metrics` na API. Hooks futuros para OpenTelemetry e Langfuse já preparados (atrás de feature flag, desligados por padrão).

Custo aproximado de LLM por chamada (tabela hardcoded $/1M tokens) emitido em log estruturado por request — base para auditoria de custo mesmo no modo "free tier".

Cluster usa Coroot/Loki potencialmente; logs JSON facilitam ingestão futura sem migração de formato.

## Tasks

- [x] Wrapper em cada subcommand CLI gerando `job_id` (uuid) propagado em `tracing::Span` _(collect; outros subcomandos quando existirem)_
- [x] Garantir que todos os logs incluem campos: `job_id` ou `request_id`, `source_id`, `raw_item_id` quando aplicável
- [x] Crate `metrics` + registro em `ai-radar-core::metrics`; `metrics-exporter-prometheus` só na API
- [x] Endpoint `/metrics` na API expondo formato Prometheus
- [x] Counters: `ai_radar_collected_total{source_type}`, `ai_radar_skipped_total{source_type}`, `ai_radar_errors_total{stage}` _(extract/scored quando T-165/T-166)_
- [x] Histogram: `ai_radar_stage_duration_seconds{stage}` _(collect)_
- [x] Gauge: `ai_radar_pending_raw_items` _(atualizado no handler `GET /metrics` via `COUNT` em Postgres)_
- [x] CronJobs emitem log estruturado de sumário no fim (`event="job.completed"`, `duration_secs`, contagens)
- [x] Cálculo de custo LLM: tabela `LlmCostTable` (modelo → $/1M tokens in/out), log `llm.request.completed` por chamada
- [x] Feature flag `otel` no Cargo.toml (default off) com stub init pronto
- [x] Stub `langfuse_export` que loga warn "not configured"
- [x] Anotar Service Kubernetes com `prometheus.io/scrape` / port / path
- [x] Test integração validando contadores incrementam após operações
- [x] Documentar smoke `/metrics` no README _(dashboards Coroot — futuro)_

## DoD

- `/metrics` retorna formato Prometheus válido.
- `kubectl logs cronjob/...` permite seguir um job inteiro pelo `job_id`.
- Build com `--features otel` e sem feature passa.
- Custo LLM aparece em log de cada chamada.
- Erros têm contexto suficiente pra debug.
- Coverage métricas ≥80%.

## Validação

```bash
cd apps/ai-radar
cargo build --features otel  # com OTEL desligado mas compilável
cargo build                  # sem feature

curl -s localhost:8080/metrics | grep ai_radar | head -20
kubectl -n ai-radar logs cronjob/ai-radar-collect | jq 'select(.event=="job.completed")'

cargo test -p ai-radar-core --test metrics
```

## References

- `docs/AI-RADAR-DECISIONS.md` — política observabilidade
- `docs/AI-RADAR-ROADMAP.md` — Fase 14
- Depende de: **T-174** (API no cluster para scrape `Service`/`/metrics`); exemplos e DoD que citam **`kubectl logs` de CronJobs** completam após **T-171**
- Branch sugerida: `feat/T-172-ai-radar-observability`
