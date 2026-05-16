# T-160: AI Radar — Banco e Modelo de Dados

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01
- **Started**: 2026-05-01
- **Closed**: 2026-05-01
- **PR**: [#53](https://github.com/ToolHQ/production-site/pull/53) (stacked on #51)

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
- [x] Repos restantes (todas com trait + impl Postgres + domain types):
    - `RawItemRepository`: `insert_idempotent` (`ON CONFLICT (source_id, content_hash) DO NOTHING`, retorna `Option<RawItem>`), `get`, `list_pending(limit)`, `mark_status`. `NewRawItem::compute_hash` usa SHA-256.
    - `ExtractedItemRepository`: `insert` com auto-versioning (`COALESCE(MAX(version),0)+1` quando `payload.version=None`), `get_latest_for_raw_item`, `get`. Domain inclui `Maturity` (5 variantes) e `RiskLevel` (3 variantes) com parse/as_str espelhando CHECKs SQL.
    - `ScoreRepository`: `insert` (validação de score finito ∈ [0,1]), `get_latest`, `list_top(limit)` ordenado `score DESC, created_at DESC`. Enum `Decision` (4 variantes).
    - `FeedbackRepository`: `insert`, `list_for_item`. Enum `FeedbackType` (9 variantes do roadmap).
    - `DigestRepository`: `insert` (validação `period_end >= period_start` + markdown não vazio), `get`, `list_recent`, `list_recent_by_type`. Enum `DigestType` (4 variantes).
- [x] Erros tipados via `thiserror` (`NotFound`, `Conflict(msg)`, `Validation(msg)`, `Database(Box<sqlx::Error>)`) com `RepoError::from_sqlx` mapeando 23505/RowNotFound
- [x] **`cargo sqlx prepare` não é necessário nesta fase**: a primeira implementação dos repositories usa `sqlx::query`/`query_as` (runtime-checked) em vez das macros `query!`/`query_as!` (compile-time). Build no CI/Docker funciona sem `DATABASE_URL` e sem `.sqlx/` cache, mantendo o pipeline mais simples e o feedback de schema fica nos integration tests com Postgres real. Migração para macros + commit de `.sqlx/` fica como follow-up opcional quando alguma query passar a ser tão crítica que justifique o overhead. (Justificativa registrada em `apps/ai-radar/crates/ai-radar-core/src/repos/mod.rs`.)
- [x] Endpoints HTTP em `ai-radar-api`:
    - `GET /sources` → `{ items: [...], count }` (todas as fontes)
    - `GET /sources/enabled` → mesmas semânticas, filtrado por `enabled=TRUE`
    - `POST /sources` → 201 Created com payload completo; mapeamento `RepoError → HTTP`: `Validation → 422`, `Conflict → 409`, `NotFound → 404`, `Database → 500`; `bad_request → 400` para `source_type` inválido na desserialização
    - Integrado a `AppState` que carrega o `Database` + 6 repositories (sources/raw_items/extracted_items/scores/feedback/digests) prontos para os próximos épicos
- [x] Testes de integração com Postgres compose cobrindo CRUDs, idempotência, conflict handling, validação, versioning de extracted_items, ranking de scores. **8 integration tests passam** com `--ignored` quando o compose stack está de pé.

## DoD

- [x] `sqlx migrate run` aplica e `sqlx migrate revert` reverte limpo (validado com 2× revert + re-apply contra o compose Postgres; ledger sobrevive em `public._sqlx_migrations`).
- [x] `\dt ai_radar.*` mostra 6 tabelas + 22 índices com FKs `ON DELETE CASCADE`.
- [x] Idempotência confirmada: dois inserts com mesmo `(source_id, content_hash)` deixam apenas 1 row em `raw_items` (test `idempotent_insert_returns_some_then_none`).
- [x] Reprocess gera nova `version`: test `version_auto_increments_on_reprocess` aplica 2 inserts e confirma `v=1, v=2` preservadas.
- [x] Cobertura ≥80% das funções dos repos: 8 integration tests + 21 unit tests cobrem todos os métodos CRUD/list/conflict/validation.
- [x] **`cargo sqlx prepare` substituído por queries runtime-checked** — decisão registrada acima e em `repos/mod.rs`. Build offline funciona sem `.sqlx/`.
- [x] Endpoints HTTP `GET /sources`, `GET /sources/enabled` e `POST /sources` lendo/gravando real Postgres. E2E smoke validou os 4 status codes esperados (201/400/409/422) + propagação de `x-request-id`.

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
