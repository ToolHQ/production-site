# T-297: Node Fleet v2 — UI mockup DNOR (tabela unificada + sparklines reais + shell)

- **Status**: In Progress
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: Node Fleet / rs-observability-api web-v2
- **Est**: 3w

## Context

O mockup de referência (`Generated_image.png`) define a visão alvo do **Node Fleet** em `reports.dnor.io`:

1. **Hero card honeypot** — card laranja destacado com radar, descrição, IP copiável, métricas + sparklines, badge Classified e tags.
2. **Tabela unificada de fleet** — colunas Status, Node, Environment, IP, ASN, Total Requests, Last 24H, Classified, Actions (não só K8s CPU/Mem/Disk).
3. **Sparklines reais** — séries temporais de requests (não decorativas).
4. **Shell DNOR** — nav Overview / Nodes / Incidents, search global, filtros de período, paginação.

Relacionado: **T-296** (dados qdbback + card básico, PRs #319–#328). Este epic eleva a **experiência visual e o modelo de dados da UI**.

### Entregas parciais

| Fase | Escopo | Status |
|------|--------|--------|
| **5d-a** | Hero card premium (radar, copy IP, bar sparklines decorativas) | ✅ PR [#331](https://github.com/ToolHQ/production-site/pull/331) |
| **5d-b** | API séries temporais honeypot (`/internal/threats-timeseries` ou similar) | ⬜ |
| **5d-c** | Sparklines reais no hero + células da tabela | ⬜ |
| **5d-d** | Tabela fleet unificada (K8s + external/honeypot) | ⬜ |
| **5d-e** | Shell DNOR (nav, search ⌘K, filtros, paginação) | ⬜ |

## Tasks

### Fase 5d-a — Hero card (concluída)

- [x] Redesign `HoneypotThreatsCard` → layout hero 3 colunas
- [x] Radar SVG animado + badge ambiente
- [x] IP copiável + métricas Total/24h/Classified/Tags
- [x] PR #331 merge + deploy rs-observability-api

### Fase 5d-b — Backend timeseries

- [ ] qdbback: endpoint agregado por hora (últimas 24h / 7d) em SQLite
- [ ] Allowlist OCI + scrape em `rs-observability-api` (`fetch_honeypot_timeseries`)
- [ ] Campo `.honeypot.nodes[].timeseries` em `/api/live/overview`

### Fase 5d-c — Sparklines reais

- [ ] Substituir `HoneypotBarSparkline` decorativo por `MetricSparkline` com dados reais
- [ ] Mini sparklines nas colunas Total Requests / Last 24H da tabela fleet

### Fase 5d-d — Tabela fleet unificada

- [ ] Modelo de linha unificado: K8s nodes + external nodes (honeypot, Hetzner, SSD)
- [ ] Colunas: Status, Node, Environment, IP, ASN, Total Requests, Last 24H, Classified
- [ ] Honeypot row destacada + link para monitor admin `:3500`
- [ ] Export CSV/JSON com novos campos

### Fase 5d-e — Shell DNOR

- [ ] Nav top-level (Overview, Nodes, Incidents, Reports, Intel, Settings)
- [ ] Search global nodes/IPs/ASNs
- [ ] Filtro período (Last 24h) + paginação
- [ ] Alinhar tipografia/cores ao mockup (dark premium)

## Critérios de aceite (epic completo)

- [ ] Hero card visualmente alinhado ao mockup (validado live)
- [ ] Sparklines refletem dados reais do qdbback (não seed sintético)
- [ ] Tabela exibe honeypot na mesma grid que demais nós externos
- [ ] ASN visível para nós com metadata disponível
- [ ] Harness live: deploy + API + screenshot MCP

## Referências

- Mockup: `~/Generated_image.png`
- UI atual: `apps/rs-observability-api/web-v2/src/components/NodesPanel.tsx`
- API honeypot: `apps/rs-observability-api/src/main.rs` (`fetch_honeypot_overview`)
- qdbback summary: `apps/qdbback/handlers/internalThreatSummaryHandler.js`
