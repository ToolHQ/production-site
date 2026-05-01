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

- [x] Migration `0001_init.up.sql`: `CREATE SCHEMA IF NOT EXISTS ai_radar` + extension `pgcrypto` + tabela `sources` com CHECK em `source_type` (`rss`,`github_repo`,`github_releases`,`webpage`,`youtube`), CHECK em `poll_interval_minutes ∈ [1,1440]`, UNIQUE(`source_type`,`url`), índice parcial em `enabled=TRUE`, trigger `tg_touch_updated_at`
- [x] Migration `0002_pipeline.up.sql`: tabelas `raw_items` (UNIQUE `source_id,content_hash` + CHECK status), `extracted_items` (CHECK maturity/risk/version + UNIQUE `raw_item_id,version`), `scores` (CHECK score 0–1 + decision adopt/test/monitor/ignore + UNIQUE `extracted_item_id,scoring_version`), `feedback` (CHECK 9 tipos), `digests` (CHECK type/period). FKs CASCADE. Índices em `collected_at DESC`, `score DESC,decision`, `category`, etc. **22 índices totais**.
- [x] Migrations `.down.sql` correspondentes — `DROP SCHEMA ai_radar CASCADE` em 0001 (seguro porque ledger SQLx fica em `public._sqlx_migrations` via `?options=-csearch_path%3Dpublic` no DATABASE_URL); `pgcrypto` preservado (compartilhado com cluster)
- [x] Configurar pool SQLx em `ai-radar-core::db` com `max_connections=8`, `min_connections=1`, `acquire_timeout=5s` + `Database::connect`/`connect_with(PoolConfig)`/`migrate()` + `RepoError` tipado (`NotFound`/`Conflict`/`Validation`/`Database`) com `RepoError::from_sqlx` mapeando 23505→Conflict e RowNotFound→NotFound
- [x] Trait `SourceRepository` (async-trait) + impl `PgSourceRepository` com `list_enabled`, `list_all`, `get`, `create` (validação + INSERT com COALESCE para defaults), `update` (PATCH semantics via COALESCE), `set_enabled`, `touch_polled` (last_polled_at + last_error). Domínio com `SourceType` enum, `Source`, `NewSource`, `SourceUpdate` + 4 unit tests + 4 integration tests (`crud_roundtrip`, `unique_url_violation_returns_conflict`, `validation_blocks_blank_name`, `touch_polled_records_error`) `#[ignore]` por padrão
- [ ] Repos restantes: `RawItemRepository` (insert idempotente, list_unprocessed, mark_status), `ExtractedItemRepository`, `ScoreRepository`, `FeedbackRepository`, `DigestRepository`
- [x] Erros tipados via `thiserror` (`NotFound`, `Conflict(msg)`, `Validation(msg)`, `Database(Box<sqlx::Error>)`) com `RepoError::from_sqlx` mapeando 23505/RowNotFound
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
