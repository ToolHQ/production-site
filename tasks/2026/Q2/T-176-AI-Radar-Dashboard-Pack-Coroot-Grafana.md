# T-176: AI Radar — Dashboard pack (Coroot / Grafana)

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 2h

## Context

A **Camada A** da Fase 16: operadores precisam ver saúde do pipeline (`ai_radar_pending_raw_items`, duração por stage, falhas) em **Coroot/Grafana** sem abrir o console de produto (**T-175**).

Reutiliza `GET /metrics` já exposto no Ingress; zero código Rust novo no hot path — apenas artefatos versionados e documentação.

## Tasks

- [ ] Inventariar métricas `ai_radar_*` expostas hoje
- [ ] Criar `apps/ai-radar/observability/grafana/ai-radar-pipeline.json` (dashboard importável)
- [ ] Documentar painéis Coroot equivalentes (ou screenshot + queries PromQL)
- [ ] README: link “Ops dashboard” + alertas sugeridos (fila pending alta, `score_failed_total`)
- [ ] Smoke: métricas visíveis após scrape do Service `ai-radar-api`

## DoD

- Operador diagnostica pipeline sem `curl` à API de produto.
- JSON de dashboard commitado no repo; passos de import em ≤ 1 página de doc.

## References

- Depende de: **T-172**
- Segue: **T-175** (mesma Fase 16; pode rodar em paralelo)
- Branch sugerida: `feat/T-176-ai-radar-dashboards`
