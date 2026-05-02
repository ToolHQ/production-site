# T-161: AI Radar — RSS Collector

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Primeiro collector funcional: lê feeds RSS/Atom, normaliza em `NewRawItem`, deduplica por `content_hash` e persiste em `raw_items`. Habilita o CLI `ai-radar collect` com isolamento de erro por fonte (uma fonte quebrada não derruba o job inteiro).

Crate base: `feed-rs` (parser estável, baixa memória). Concurrency limitada (default 2) via `futures::stream::buffer_unordered` para o cluster pequeno. User-Agent identificável `ai-radar/<version>`.

## Tasks

- [ ] Trait `Collector` em `ai-radar-core::collector` com `collect(&self, source: &Source) -> Result<Vec<NewRawItem>>`
- [ ] `RssCollector` usando `reqwest` (timeout 15s, redirect cap 5) + `feed-rs::parser::parse`
- [ ] Mapping de `feed_rs::Entry` → `NewRawItem` (title, url, published_at, raw_content)
- [ ] Função `compute_hash(item)` em `util/hash.rs` (SHA-256 de `url || normalize(title) || normalize(body)`)
- [ ] `RawItemRepository::upsert_skip_existing` usando `INSERT ... ON CONFLICT (source_id, content_hash) DO NOTHING RETURNING id`
- [ ] Pipeline `pipeline/collect.rs::run()` itera sources enabled, chama collector adequado, persiste, agrega métricas
- [ ] Migration `0003_source_last_error.up.sql` adicionando `last_error text, last_error_at timestamptz, last_polled_at timestamptz` em `sources`
- [ ] Subcommand CLI `ai-radar collect [--source-id <uuid>] [--source-type rss]` em `clap`
- [ ] Concurrency configurável via `AI_RADAR_COLLECT_CONCURRENCY` (default 2)
- [ ] Erro isolado por fonte: log + persistência em `sources.last_error`, job continua
- [ ] Limite `max_items_per_run` configurável (default 50)
- [ ] Sumário stdout: `collected=X skipped=Y errors=Z`
- [ ] Fixtures XML em `tests/fixtures/rss/*.xml` para testes offline
- [ ] Teste integração: 2 sources (uma OK, uma 500) → exit 0, erro logado

## DoD

- Adicionar source RSS via `POST /sources` e rodar `ai-radar collect` traz items reais.
- 2ª execução do mesmo feed não duplica (0 inserts).
- Source quebrada não impede outras (exit 0 a menos que TODAS falhem).
- Erro fica registrado em `sources.last_error`.
- Sumário stdout correto.
- Coverage testes ≥80%.

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
cargo test -p ai-radar-core --test rss_collector
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 3
- Depende de: **T-160**
- Branch sugerida: `feat/T-161-ai-radar-rss-collector`
