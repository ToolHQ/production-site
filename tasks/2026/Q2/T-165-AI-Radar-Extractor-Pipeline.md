# T-165: AI Radar — Extractor Pipeline

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Pipeline que transforma `raw_items` em `extracted_items` estruturados via LLM. Prompt versionado (`v1`) extrai campos: `title, tool_name, category, problem_solved, target_users, stack_fit, self_hosted, saas_only, license, maturity, risk_level, summary, key_points, recommended_action`.

Validação com `serde_json::from_str::<ExtractedFields>`. Fallback robusto: detecta code fences ` ```json ... ``` `, retry com prompt corretivo, depois falha controlada. Truncar `raw_content` a 8000 chars antes de enviar para controlar custo.

Concurrency=1 no MVP (jobs curtos via cron, não worker 24/7).

## Tasks

- [ ] `extractor/prompt.rs` exporta `EXTRACTOR_PROMPT_V1` (string) + `extractor_version() -> &str = "v1"`
- [ ] Prompt instrui: "Responda somente JSON válido, sem Markdown, sem code fences"
- [ ] Struct `ExtractedFields` em `extractor/schema.rs` deserializável (campos opcionais com `null` permitido)
- [ ] Truncate de input a `MAX_EXTRACT_INPUT_TOKENS≈8000` (chars-aprox)
- [ ] `pipeline/extract.rs::run(limit)` itera `raw_items WHERE status='pending'`
- [ ] Chamada LLM via `LlmProvider` com `json_mode=true` quando suportado
- [ ] Parser robusto: remove code fences se presentes
- [ ] Retry com prompt corretivo: "Sua resposta anterior não foi JSON válido. Repita apenas o JSON, sem texto adicional"
- [ ] Persistir `ExtractedItem` com `version=1` (ou +1 se reprocess); status do raw_item → `extracted` ou `extract_failed`
- [ ] Auditoria: persistir `extract_attempts` em `metadata_json`
- [ ] CLI subcommand `ai-radar extract [--limit N]` com sumário `extracted=X failed=Y`
- [ ] Testes com Mock provider: JSON perfeito, JSON em code fence, JSON inválido em ambas tentativas
- [ ] Endpoint `POST /extract/run` para trigger via API

## DoD

- `ai-radar extract --limit 10` processa até 10 items.
- Mock retornando JSON válido → extracted_item criado.
- Mock retornando ` ```json ... ``` ` → parse OK.
- Mock retornando lixo nas 2 tentativas → `extract_failed`, raw_item preservado para retry futuro.
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
