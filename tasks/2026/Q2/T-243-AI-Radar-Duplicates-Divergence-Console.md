# T-243: AI Radar — Duplicates & Divergence Console

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Backend já expõe:

- `GET /reports/duplicates` — clusters por `tool_key` (**T-231**)
- `GET /reports/divergence` — feedback vs decisão do scorer (**T-170**)

Falta superfície no Operator Console para curadoria humana sem `curl`.

## Tasks

- [ ] Nav **Relatórios** (ou sub-itens Duplicatas / Divergência)
- [ ] `#/reports/duplicates` — tabela clusters, contagem, link para líder `extracted`
- [ ] `#/reports/divergence` — tipo feedback, score, decisão, item id
- [ ] Estados vazio/erro/loading consistentes com Explorer
- [ ] README smoke: duas URLs no runbook **T-191**

## Dependências

- **T-231** ✅ API duplicates
- **T-170** ✅ API divergence
- **T-175** ✅ console shell

## Validação

- `curl` smoke + browser em `https://ai-radar.dnor.io/#/reports/duplicates`
