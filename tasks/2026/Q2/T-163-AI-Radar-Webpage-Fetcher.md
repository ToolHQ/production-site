# T-163: AI Radar — Webpage Fetcher

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h
- **Opened**: 2026-05-01

## Context

Permite cadastrar URLs manuais arbitrárias (ex.: documentação de uma tool, blog post fora de RSS) e processá-las como `raw_items`. Fetcher HTTP com timeout, max-size (1MB) e cleaner HTML que remove `<script>`, `<style>`, comentários e whitespace excessivo.

Sem JS rendering (limitação documentada). Crate inicial: `scraper` (simples). Migrar para `lol_html` se memória apertar no cluster.

## Tasks

- [x] Struct `WebFetcher` em `ai-radar-core::collector::web::fetcher` com config (timeout 20s, max-size 1MB, redirect cap 5)
- [x] `fetch(url) -> Result<RawHtml>` com cut-off de Content-Length e streaming guard
- [x] Função `extract(html) -> CleanContent { title, text }` em `cleaner.rs` usando `scraper`
- [x] Limite de saída: 50KB de texto pós-clean (truncar com indicação)
- [x] Normalizar whitespace; preservar quebras de parágrafo
- [x] Despacho no pipeline collect para `source_type='webpage'`
- [x] Fixtures HTML em `tests/fixtures/web/*.html` (página com script, iframe, inline css, página gigante)
- [x] Teste: payload >1MB → erro claro
- [x] Teste: HTML com script/style → texto limpo conforme expected
- [x] Documentar limitação "sem JS rendering" no README

## DoD

- URL manual cadastrada vira `raw_item` com conteúdo limpo, ≤50KB.
- Página >1MB rejeitada com mensagem clara.
- Memória estável durante fetch de páginas grandes (não explode).
- Coverage testes ≥80%.

## Validação

```bash
cd apps/ai-radar
curl -X POST localhost:8080/sources -H 'Content-Type: application/json' \
  -d '{"name":"Some doc","source_type":"webpage","url":"https://example.com/docs"}'

cargo run -p ai-radar-cli -- collect --source-type webpage
psql $DATABASE_URL -c "SELECT title, length(raw_content) FROM ai_radar.raw_items WHERE source_id IN (SELECT id FROM ai_radar.sources WHERE source_type='webpage') LIMIT 5"
cargo test -p ai-radar-core --test web_fetcher
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 5
- Depende de: **T-160** (paralelizável com T-161/T-162)
- Branch sugerida: `feat/T-163-ai-radar-webpage-fetcher`
