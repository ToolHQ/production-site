# T-249: AI Radar — Semantic Search API

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Operadores precisam encontrar ferramentas por intenção (“observability self-hosted k8s”), não só filtros estruturados (**T-244**).

## Tasks

- [ ] `GET /search?q=&limit=&category=` — embed query + cosine vs `item_embeddings`
- [ ] Resposta: `ScoredItemSummary` + `similarity` (0–1)
- [ ] Fallback: se `EMBEDDINGS_ENABLED=false` → 503 ou busca lexical simples em `summary`/`tool_name`
- [ ] Rate limit leve (reuse padrão API)
- [ ] Teste integração com vetores fixture

## Dependências

- **T-247**, **T-248** ✅ dados embedados

## Validação

- `curl '/search?q=vector+database+self+hosted&limit=5'`
