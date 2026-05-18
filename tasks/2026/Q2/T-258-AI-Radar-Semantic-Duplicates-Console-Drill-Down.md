# T-258: AI Radar — Semantic Duplicates Console Drill-Down

- **Status**: In Progress
- **Priority**: 🔽 Low
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Relatório `GET /reports/semantic-duplicates` e rota `#/reports/semantic-duplicates` listam pares, mas não permitem abrir os dois itens lado a lado nem marcar para revisão manual (dedup semântico continua **somente leitura** — sem auto-merge).

## Tasks

- [x] Cada par: links para `#/items/{id}` dos dois `extracted_item_id`
- [x] Colunas: tool_name, category, score, similarity %
- [x] Filtro por threshold no UI (slider + `?threshold=` na URL)
- [x] Empty state quando `scanned < 10` embeddings (hint backfill)
- [x] API: `score_a` / `score_b` no payload de pares

## Definition of Done

- Stakeholder clica num par e vê detalhes dos dois itens
- Threshold ajustável sem editar URL manualmente

## Validação

Console → Relatórios → Duplicatas semânticas → abrir par → detalhe do item.
