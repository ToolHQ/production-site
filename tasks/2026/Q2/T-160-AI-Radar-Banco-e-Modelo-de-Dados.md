# T-160: AI Radar — Banco e Modelo de Dados

- **Status**: In Progress
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01
- **Started**: 2026-05-01

## Context

Schema versionado e camada de repositórios SQLx para persistir todo o pipeline do AI Radar. Usa o **Postgres compartilhado do cluster** com schema dedicado `ai_radar` (sem subir banco novo).

Tabelas mínimas (vide `docs/AI-RADAR-DECISIONS.md`): `sources`, `raw_items`, `extracted_items`, `scores`, `feedback`, `digests`. Constraints críticas: `(source_id, content_hash)` UNIQUE em `raw_items` para idempotência, `version int` em `extracted_items`/`scores` para reprocess, `metadata_json jsonb` para extensibilidade.

SQLx com `rustls` (sem `openssl-sys`) — crítico para build distroless ARM64.

## Tasks

- [ ] Migration `0001_init.up.sql`: `CREATE SCHEMA IF NOT EXISTS ai_radar` + extension `pgcrypto` (uuid v4) + tabela `sources` com CHECK constraint em `source_type` (`rss`, `github_repo`, `github_releases`, `webpage`, `youtube`)
- [ ] Migration `0002_pipeline.up.sql`: tabelas `raw_items`, `extracted_items`, `scores`, `feedback`, `digests` com FKs e índices (`raw_items(collected_at DESC)`, `scores(score DESC, decision)`)
- [ ] Migrations `.down.sql` correspondentes para todas as up
- [ ] Configurar pool SQLx em `ai-radar-core::db` com `max_connections=8`, `min_connections=1`, `acquire_timeout=5s`
- [ ] Trait `SourceRepository` + impl Postgres com métodos `list_enabled`, `get`, `create`, `update`, `set_enabled`
- [ ] Repos restantes: `RawItemRepository` (insert idempotente, list_unprocessed, mark_status), `ExtractedItemRepository`, `ScoreRepository`, `FeedbackRepository`, `DigestRepository`
- [ ] Erros tipados via `thiserror` (`NotFound`, `Conflict`, `Database`)
- [ ] `cargo sqlx prepare` para builds offline (commitar `.sqlx/`)
- [ ] Endpoints `GET /sources` e `POST /sources` lendo/gravando do banco real
- [ ] Testes de integração com Postgres (testcontainers ou compose dedicado de teste) cobrindo CRUDs + idempotência

## DoD

- `sqlx migrate run` aplica e `sqlx migrate revert` reverte limpo.
- `\d ai_radar.sources` e demais tabelas mostram schema esperado com FKs/indexes.
- Inserir mesmo `(source_id, content_hash)` 2x → segundo insert é Skipped (sem erro, sem duplicata).
- Reprocess gera nova `version`, antiga preservada.
- Cobertura de testes ≥80% das funções dos repos.
- `cargo sqlx prepare` atualizado e commitado.

## Validação

```bash
cd apps/ai-radar
sqlx migrate run
psql $DATABASE_URL -c "\dt ai_radar.*"
cargo test --workspace -- --include-ignored  # integração c/ Postgres
sqlx migrate revert
psql $DATABASE_URL -c "\dn" | grep -v ai_radar  # schema removido
```

## References

- `docs/AI-RADAR-DECISIONS.md` — modelo de dados completo
- `docs/AI-RADAR-ROADMAP.md` — Fase 2
- Depende de: **T-159**
- Branch sugerida: `feat/T-160-ai-radar-database-layer`
