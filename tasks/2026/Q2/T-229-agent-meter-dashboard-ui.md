# T-229 — agent-meter: Dashboard UI

**Owner**: OpenCode
**Priority**: 🔼 High
**Estimate**: 3h
**Status**: Backlog

## Goal

Build a dedicated UI dashboard for agent-meter beyond the embedded HTML stub. Options: Vite+Preact (like Cluster Pulse), or a richer single-page app.

## Existing state

`GET /` serve uma dashboard HTML embarcada via `include_str!` em `routes/dashboard.rs` — dark theme, KPI cards, tabbed reports (top tools / tasks / servers), test-event form. Funciona mas é limitada.

## Tasks

- [ ] Avaliar se Vite+Preact é overkill vs evoluir o embedded HTML com HTMX ou JS vanilla
- [ ] Implementar filtros por período (última 1h, 6h, 24h, 7d, 30d)
- [ ] Implementar gráficos sparkline de chamadas ao longo do tempo
- [ ] Implementar visualização de OTEL spans/traces
- [ ] Botão de export CSV nos reports
- [ ] Tema escuro consistente com Cluster Pulse

## Dependencies

- T-225 (OTEL docs) para schema de spans
- Collector endpoints já existem

## Acceptance Criteria

- Dashboard funcional sem refresh manual
- Dados de 3+ reports visíveis simultaneamente
- Responsivo (mobile ok)
