# T-250: AI Radar — Explorer Semantic Search UI

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Expor **T-249** no Operator Console — barra de busca semântica no Explorer.

## Tasks

- [ ] `#/items` — campo “Busca semântica” + debounce + resultados com % similaridade
- [ ] Estado vazio / embeddings desabilitados (mensagem clara)
- [ ] Persistir `?q=` em `location.search` (como filtros **T-244**)
- [ ] Smoke browser em https://ai-radar.dnor.io/#/items

## Dependências

- **T-249** ✅

## Validação

- Buscar termo conhecido → lista com scores de similaridade
