# T-258: AI Radar — Semantic Duplicates Console Drill-Down

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Relatório `GET /reports/semantic-duplicates` e rota `#/reports/semantic-duplicates` listam pares, mas não permitem abrir os dois itens lado a lado nem marcar para revisão manual (dedup semântico continua **somente leitura** — sem auto-merge).

## Tasks

- [ ] Cada par: links para `#/items/{id}` dos dois `extracted_item_id`
- [ ] Colunas: tool_name, category, score, similarity %
- [ ] Filtro por threshold no UI (slider ou input, repassa `?threshold=`)
- [ ] Empty state quando `scanned < 10` embeddings (link para runbook T-256)
- [ ] Smoke browser na página de duplicatas

## Definition of Done

- Stakeholder clica num par e vê detalhes dos dois itens
- Threshold ajustável sem editar URL manualmente

## Validação

Console → Relatórios → Duplicatas semânticas → abrir par → detalhe do item.
