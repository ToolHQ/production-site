# T-262: AI Radar — Explorer Sem-Embedding Badge

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 3h

## Context

Itens sem vetor não são visíveis na lista do Explorer — operador não sabe o que falta embedar.

## Tasks

- [x] API lista: flag `has_embedding` por item (EXISTS em `item_embeddings`)
- [x] Badge “sem vetor” na tabela Explorer
- [x] Filtro opcional `?has_embedding=false`

## Definition of Done

- Lista mostra quais scored items ainda não têm embedding
