# T-165: AI Radar — Extractor Pipeline

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Pipeline que transforma `raw_items` em `extracted_items` estruturados via LLM. Prompt versionado (`v1`) extrai campos: `title, tool_name, category, problem_solved, target_users, stack_fit, self_hosted, saas_only, license, maturity, risk_level, summary, key_points, recommended_action`.

Validação com `serde_json::from_str::<ExtractedFields>`. Fallback robusto: detecta code fences ` ```json ... ``` `, retry com prompt corretivo, depois falha controlada. Truncar `raw_content` a 8000 chars antes de enviar para controlar custo.

Concurrency=1 no MVP (jobs curtos via cron, não worker 24/7).

## Tasks

- [x] `extractor/prompt.rs` exporta `EXTRACTOR_PROMPT_V1` + `EXTRACTOR_VERSION` + `extractor_id()` (`llm-v1`)
- [x] Prompt instrui JSON-only (sem markdown / code fences)
- [x] Struct `ExtractedFields` em `extractor/schema.rs` deserializável (`Option` + `key_points` como `Value`)
- [x] Truncate de input via `MAX_EXTRACT_INPUT_CHARS` (= 8000 chars, alinhado a `MAX_EXTRACT_INPUT_TOKENS`)
- [x] `pipeline/extract::run_extract` + `claim_pending_batch` (`pending` → `extracting` FIFO, `SKIP LOCKED`)
- [x] Chamada LLM via `LlmProvider` com `json_mode=true`
- [x] Parser robusto (`strip_json_fences` + `serde_json`)
- [x] Segunda tentativa com prompt corretivo + trecho da resposta anterior
- [x] Persistir `ExtractedItem` (`extractor=llm-v1`, version auto); `raw_items.status` → `extracted` ou `failed` (SQL; não há `extract_failed`)
- [x] Auditoria: `extract_attempts` em `extracted_items.metadata_json` (sucesso) e `raw_items.metadata_json` (falha)
- [x] CLI `extract --limit N` → `extracted=X failed=Y`
- [x] Testes `tests/extractor.rs` (mock JSON, fence, lixo×2)
- [x] `POST /extract/run` na API

## DoD

- `ai-radar extract --limit 10` processa até 10 items.
- Mock retornando JSON válido → extracted_item criado.
- Mock retornando ` ```json ... ``` ` → parse OK.
- Mock retornando lixo nas 2 tentativas → `raw_items.status=failed` + `extract_attempts` no metadata (re-enfileirar manualmente se necessário).
- Custo LLM logado por chamada.
- Coverage testes ≥80%.

## Validação

```bash
cd apps/ai-radar
export LLM_ENABLED=true
export LLM_API_KEY=sk-or-...

# Pipeline pré-existente: collect já rodou e há raw_items pending
cargo run -p ai-radar-cli -- extract --limit 5
psql $DATABASE_URL -c "SELECT tool_name, category, summary FROM ai_radar.extracted_items LIMIT 5"
psql $DATABASE_URL -c "SELECT status, count(*) FROM ai_radar.raw_items GROUP BY status"

cargo test -p ai-radar-core --test extractor
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 7
- Depende de: **T-164** + **T-161** (≥1 collector funcional)
- Branch sugerida: `feat/T-165-ai-radar-extractor-pipeline`
