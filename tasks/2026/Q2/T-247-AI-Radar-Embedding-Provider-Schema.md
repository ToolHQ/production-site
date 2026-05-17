# T-247: AI Radar — Embedding Provider & Schema

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

Fases 17–18 cobriram curadoria determinística e console operacional. A **Fase 19** abre **semântica leve**: vetores para busca e dedup além de `tool_key` (**T-231**).

**Restrições:** reutilizar gateway OpenRouter-compatible já usado pelo LLM; sem pgvector obrigatório no MVP — armazenar `REAL[]` ou `JSONB` + cosine em Rust; feature flag `EMBEDDINGS_ENABLED=false` default.

## Tasks

- [ ] Migration `0007_item_embeddings`: `extracted_item_id`, `model`, `dimensions`, `vector` (pg array ou jsonb), `created_at`
- [ ] Trait `EmbeddingProvider` + impl OpenRouter (`/embeddings`) alinhada a `LlmProvider`
- [ ] Config: `EMBEDDING_MODEL`, `EMBEDDING_ENABLED`, dimensão fixa documentada
- [ ] Repo `PgItemEmbeddingRepository` — upsert idempotente por `(extracted_item_id, model)`
- [ ] Testes unitários com vetor fixture + cosine helper

## Dependências

- **T-164** ✅ LLM abstraction
- **T-165** ✅ extract pipeline

## Validação

- `cargo test -p ai-radar-core embedding`
- Migration aplicada no Postgres cluster
