# T-176: AI Radar — Dashboard pack (Coroot / Grafana)

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 2h

## Context

A **Camada A** da Fase 16: operadores precisam ver saúde do pipeline (`ai_radar_pending_raw_items`, duração por stage, falhas) em **Coroot/Grafana** sem abrir o console de produto (**T-175**).

Reutiliza `GET /metrics` já exposto no Ingress; zero código Rust novo no hot path — apenas artefatos versionados e documentação.

## Tasks

- [x] Inventariar métricas `ai_radar_*` expostas hoje
- [x] Criar `apps/ai-radar/observability/grafana/ai-radar-pipeline.json` (dashboard importável)
- [x] Documentar painéis Coroot equivalentes + queries PromQL em `observability/README.md`
- [x] README: link “Ops dashboard” + alertas sugeridos (`alerting-rules.example.yaml`)
- [x] Smoke: métricas no Prometheus Coroot (`ai_radar_pending_raw_items` com labels `namespace=ai-radar`)

## DoD

- Operador diagnostica pipeline sem `curl` à API de produto.
- JSON de dashboard commitado no repo; passos de import em ≤ 1 página de doc.

## References

- Depende de: **T-172**
- Segue: **T-175** (mesma Fase 16; pode rodar em paralelo)
- Branch sugerida: `feat/T-176-ai-radar-dashboards`
