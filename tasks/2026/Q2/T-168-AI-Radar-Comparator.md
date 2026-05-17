# T-168: AI Radar — Comparator

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 4h
- **Opened**: 2026-05-01

## Context

Compara ferramentas da **mesma categoria** (LLM observability, AI coding agents, MCP servers, RAG frameworks, Vector DBs, Browser automation, etc) gerando matriz com critérios derivados de `extracted_items` + `metadata_json`:

- Self-hosted, K8s-friendly, license_clarity, maturity, last_activity, doc_quality

Cada critério vira score 0-3. Resultado renderizado como Markdown legível e persistido em tabela `comparisons` para audit/replay.

## Tasks

- [x] Migration `0004_comparisons.up.sql`: `comparisons (id, category, top_n, matrix_json, markdown, generated_at)`
- [x] `Comparator::compare(category: &str, top_n: usize)` em `ai-radar-core::comparator`
- [x] Função pura que mapeia `ExtractedItem` + `Score` → `CriteriaScores` (6 critérios 0-3)
- [x] Renderer Markdown produzindo tabela legível
- [x] Endpoint `POST /compare { category, top_n }` retornando Markdown
- [x] CLI `ai-radar compare --category "LLM observability" --top 5`
- [x] Validação: jamais comparar entre categorias distintas
- [x] Persistir resultado em `comparisons`
- [x] Snapshot test do Markdown gerado
- [x] Fixtures com 5 ExtractedItems na mesma categoria

## DoD

- Categoria com 3+ tools produz matriz não-trivial.
- Markdown bem formatado (renderiza no GitHub preview).
- Resultado persistido permite replay/audit.
- Categorias incompatíveis nunca misturadas.
- Coverage ≥80%.

## Validação

```bash
cd apps/ai-radar
cargo run -p ai-radar-cli -- compare --category "LLM observability" --top 5
# OU
curl -X POST localhost:8080/compare -H 'Content-Type: application/json' \
  -d '{"category":"LLM observability","top_n":5}' | head -50

psql $DATABASE_URL -c "SELECT category, top_n, generated_at FROM ai_radar.comparisons ORDER BY generated_at DESC LIMIT 5"
cargo test -p ai-radar-core --test comparator
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 10
- Depende de: **T-166**
- Branch: `feat/T-168-comparator`
