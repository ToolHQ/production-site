# T-229 — agent-meter: Dashboard UI

**Owner**: OpenCode
**Priority**: 🔼 High
**Estimate**: 3h
**Status**: ✅ Done

## Goal

Build a dedicated UI dashboard for agent-meter beyond the embedded HTML stub. Options: Vite+Preact (like Cluster Pulse), or a richer single-page app.

## Existing state

`GET /` serve uma dashboard HTML embarcada via `include_str!` em `routes/dashboard.rs` — dark theme, KPI cards, tabbed reports (top tools / tasks / servers), test-event form. Funciona mas é limitada.

## Realizado (PR #177)

**Decisão**: Vite+Preact considerado overkill — mantido embedded HTML com vanilla JS + SVG.

- [x] Filtros por período (1h, 6h, 24h, 7d, 30d) com botões tipo pill
- [x] Sparkline SVG de chamadas ao longo do tempo (com auto-bucket: minute/hour/day)
- [x] KPI cards: total calls, total tokens, avg tokens/call, error rate, MCP servers, period
- [x] CSV export em cada aba de report
- [x] Tabs: Top Tools, Top Tasks, Top MCP Servers — visíveis simultaneamente via troca de aba
- [x] Auto-refresh: health 15s, reports 5s, sparkline 15s
- [x] Tema escuro (Inter font, design consistente com Cluster Pulse)
- [x] Responsivo (grid collapse em mobile, fonte adaptável)
- [x] Formulário de teste ("Send Event" + "Send Random" para dados sintéticos)
- [ ] Pendente: visualização de OTEL spans (depende de dados OTEL reais fluindo)

## Dependencies

- T-225 (OTEL docs) — Done

## Acceptance Criteria

- ✅ Dashboard funcional sem refresh manual (auto-polling 5s)
- ✅ Dados de 3+ reports visíveis (tools/tasks/servers via tabs)
- ✅ Responsivo (mobile breakpoint @768px)
