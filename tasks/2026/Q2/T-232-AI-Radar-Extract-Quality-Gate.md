# T-232: AI Radar — Extract Quality Gate

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

O extractor LLM (**T-165**) aceita JSON com fallback, mas não havia **score de qualidade** nem re-fila sistemática. Itens com `tool_name` null, `category` genérica ou summary vazio passavam e recebiam score enganoso.

**Implementado:** gate determinístico pós-parse LLM em `extractor/quality.rs`, integrado em `pipeline/extract.rs`.

| Score | Ação |
| ----- | ---- |
| ≥ 70 | insert + `extracted` |
| 40–69 | insert + `quality_warn` + `low_confidence` |
| < 40 | `failed` + `extract_quality_low` (sem insert) |

## Tasks

- [x] `extractor/quality.rs`: `assess_extract_quality` + `QualityReport`
- [x] Integrar no pipeline extract (CLI + CronJob + API)
- [x] Métricas: `ai_radar_extract_quality_*` + histogram score
- [x] API/CLI: contadores `quality_warn`, `quality_rejected`
- [x] Testes unitários + `tests/extract_quality_pipeline.rs`
- [ ] Deploy cluster + validar fila pending após merge

## Validação

```bash
cargo test -p ai-radar-core --lib quality::tests
cargo test -p ai-radar-core --test extract_quality_pipeline
cargo test -p ai-radar-api
```

## Dependências

- **T-165**, **T-164** ✅
- Próximo: **T-231** entity resolution
