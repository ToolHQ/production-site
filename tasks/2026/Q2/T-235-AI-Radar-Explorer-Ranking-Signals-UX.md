# T-235: AI Radar — Explorer Ranking & Signals UX

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

Com **T-233** (adoption em `metadata_json`), o Explorer ainda mostra só decisão/score/categoria.
Operadores precisam ver **sinais de adoção** (stars tier, atividade) e ordenar/filtrar sem abrir cada item.

## Tasks

- [ ] API: expor `adoption` (stars_tier, activity_tier) em `GET /items`
- [ ] Explorer: coluna badges + filtros (tier, quality_warn)
- [ ] Sort: `adoption_desc`, manter `score_desc`
- [ ] Item detail: bloco adoption legível
- [ ] Testes + deploy API

## Dependências

- **T-233** adoption ✅
- **T-177** items API ✅

## Validação

- Explorer em https://ai-radar.dnor.io/#/items mostra badges para itens GitHub
- `curl '/items?limit=5' | jq '.items[0].adoption'`
