# T-257: AI Radar — Related Items & Semantic Empty-State UX

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 3h

## Context

`GET /items/:id/related` retorna lista vazia com `has_embedding: true` quando vizinhos estão abaixo de `MIN_RELATED_SIMILARITY` (0.55) ou em outra categoria (`same_category=true` default). O console não explica isso — parece bug.

## Tasks

- [ ] Explorer: toggle “mesma categoria” / “todas categorias” (`?same_category=`)
- [ ] Empty state: mensagem contextual (sem embedding / baixa cobertura / sem vizinhos acima do limiar)
- [ ] Opcional: query `min_similarity` no API (default 0.55) para debug operador
- [ ] Busca semântica: hint quando `count=0` mas `mode=semantic` (sugerir termos ou lexical)
- [ ] Testes API para `same_category=false` retornando mais vizinhos em fixture

## Definition of Done

- Operador entende por que related está vazio sem ler código Rust
- Com cobertura ≥30 embeddings, pelo menos um item mostra vizinhos no smoke

## Validação

Abrir item com embedding no Explorer → painel related com toggle ou mensagem clara.
