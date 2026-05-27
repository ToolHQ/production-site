# T-301: Node Fleet v2 — UI mockup DNOR (period + export + shell)

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: Node Fleet / rs-observability-api web-v2
- **Est**: 3w
- **Supersedes**: arquivo `T-297-Node-Fleet-v2-...md` (T-297 no KANBAN = task Copilot Bootstrap)

## Context

Epic de elevação visual do **Node Fleet** em `reports.dnor.io` conforme mockup DNOR (`Generated_image.png`).

Relacionado: **T-296** (dados qdbback + card básico). Este epic cobre hero premium, tabela fleet unificada, sparklines reais, shell DNOR, filtro de período e export.

## Entregas

| Fase | Escopo | PR |
|------|--------|-----|
| **5d-a** | Hero card premium (radar, copy IP) | [#331](https://github.com/ToolHQ/production-site/pull/331) |
| **5d-b** | API timeseries honeypot | [#334](https://github.com/ToolHQ/production-site/pull/334) |
| **5d-c** | Sparklines reais hero + fleet table | #331, #338 |
| **5d-d** | Tabela fleet unificada | [#338](https://github.com/ToolHQ/production-site/pull/338) |
| **5d-e** | Shell DNOR (nav, ⌘K, paginação) | [#340](https://github.com/ToolHQ/production-site/pull/340) |
| **fix** | Tooltips no scroll/wheel | [#343](https://github.com/ToolHQ/production-site/pull/343) |
| **5d-f** | Filtro período 24h/7d + export fleet JSON/CSV | [#344](https://github.com/ToolHQ/production-site/pull/344) |

## Tasks

- [x] Hero card honeypot estilo DNOR (radar, métricas, copy IP)
- [x] `GET /internal/threats-timeseries` + campos `requests_24h` / `requests_7d` na API
- [x] Sparklines reais (`MetricSparkline`) no hero e colunas da fleet table
- [x] Tabela fleet: Status, Node, Env, IP, ASN, Requests, Classified, paginação
- [x] Shell: nav hash routes, ⌘K search, filtro período
- [x] Período 24h/7d wired em hero + fleet table + export
- [x] Export JSON/CSV com seções `fleet` e `honeypot`
- [x] Deploy live + API honeypot `available: true`

## Critérios de aceite

- [x] Hero + fleet table alinhados ao mockup DNOR (validado live)
- [x] Sparklines com dados reais qdbback
- [x] Honeypot na mesma grid que nós externos
- [x] ASN visível por cluster
- [x] Filtro período altera métricas de atividade
- [x] Export inclui fleet overview

## Evidência live (2026-05-25)

- https://reports.dnor.io/#nodes — hero + fleet table + período 24h/7d
- `curl -s https://reports.dnor.io/api/live/overview | jq '.honeypot.available'` → `true`
- PR #344 merged + deploy `rs-observability-api`

## Referências

- `apps/rs-observability-api/web-v2/src/components/NodesPanel.tsx`
- `apps/rs-observability-api/web-v2/src/utils/fleetOverview.ts`
- `apps/rs-observability-api/web-v2/src/utils/export.ts`
