# T-161: AI Radar — RSS Collector

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Primeiro collector funcional: lê feeds RSS/Atom, normaliza em `NewRawItem`, deduplica por `content_hash` e persiste em `raw_items`. Habilita o CLI `ai-radar collect` com isolamento de erro por fonte (uma fonte quebrada não derruba o job inteiro).

Crate base: `feed-rs` (parser estável, baixa memória). Concurrency limitada (default 2) via `futures::stream::buffer_unordered` para o cluster pequeno. User-Agent identificável `ai-radar/<version>`.

## Tasks

- [x] Trait `Collector` em `ai-radar-core::collector` com `collect(&self, source: &Source) -> Result<Vec<NewRawItem>>`
- [x] `RssCollector` usando `reqwest` (timeout 15s, redirect cap 5) + `feed-rs::parser::parse`
- [x] Mapping de `feed_rs::Entry` → `NewRawItem` (title, url, published_at, raw_content)
- [x] Função `collector_content_hash` em `util/hash.rs` (SHA-256 de `url || normalize(title) || normalize(body)`)
- [x] Idempotência via `RawItemRepository::insert_idempotent` (`INSERT … ON CONFLICT DO NOTHING`) — equivalente ao upsert “skip existing”
- [x] Pipeline `pipeline/collect.rs::run_collect` itera sources enabled, chama RSS collector, persiste, agrega métricas
- [x] ~~Migration `0003`~~ — **não aplicável**: `sources.last_polled_at` / `sources.last_error` já existem em `0001_init.up.sql`; `touch_polled` cobre o contrato operacional
- [x] Subcommand CLI `ai-radar collect [--source-id <uuid>] [--source-type rss]` em `clap`
- [x] Concurrency configurável via `AI_RADAR_COLLECT_CONCURRENCY` (default 2)
- [x] Erro isolado por fonte: log + persistência em `sources.last_error`, job continua
- [x] Limite `AI_RADAR_MAX_ITEMS_PER_RUN` configurável (default 50)
- [x] Sumário stdout: `collected=X skipped=Y errors=Z (N sources)`
- [x] Fixture RSS em `crates/ai-radar-core/tests/fixtures/rss/minimal.rss` + testes `feed-rs` / wiremock (HTTP 200 + 500)
- [x] Isolamento HTTP coberto por testes wiremock (fonte OK vs 500); pipeline exit **1** só se todas as fontes falharem

## DoD

- Adicionar source RSS via `POST /sources` e rodar `ai-radar collect` traz items reais.
- 2ª execução do mesmo feed não duplica (0 inserts).
- Source quebrada não impede outras (exit 0 a menos que **todas** falhem).
- Erro fica registrado em `sources.last_error`.
- Sumário stdout correto.
- Coverage testes ≥80% — gate `rust-ai-radar` passa com novos testes de hash + RSS.

## Validação

```bash
cd apps/ai-radar
# Cadastrar source de teste (ex: Rust Blog)
curl -X POST localhost:8080/sources \
  -H 'Content-Type: application/json' \
  -d '{"name":"Rust Blog","source_type":"rss","url":"https://blog.rust-lang.org/feed.xml"}'

cargo run -p ai-radar-cli -- collect
# 2ª vez não deve duplicar
cargo run -p ai-radar-cli -- collect

psql $DATABASE_URL -c "SELECT count(*) FROM ai_radar.raw_items"
cargo test -p ai-radar-core collector::rss
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 3
- Depende de: **T-160**
- Branch sugerida: `feat/T-161-ai-radar-rss-collector`
