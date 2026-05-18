# T-257: AI Radar — Related Items & Semantic Empty-State UX

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 3h

## Context

`GET /items/:id/related` retorna lista vazia com `has_embedding: true` quando vizinhos estão abaixo de `MIN_RELATED_SIMILARITY` (0.55) ou em outra categoria (`same_category=true` default). O console não explica isso — parece bug.

## Tasks

- [x] Explorer: toggle “mesma categoria” / “todas categorias” (`?same_category=`)
- [x] Empty state: mensagem contextual (`empty_reason`, `best_similarity`)
- [x] Query `min_similarity` no API (default 0.55)
- [x] Busca semântica: hint quando `count=0` e `mode=semantic`
- [x] Testes deserialize `RelatedQuery` (`same_category=false`, defaults)

## Definition of Done

- Operador entende por que related está vazio sem ler código Rust
- Com cobertura ≥30 embeddings, pelo menos um item mostra vizinhos no smoke

## Validação

Abrir item com embedding no Explorer → painel related com toggle ou mensagem clara.
