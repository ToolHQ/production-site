# T-248: AI Radar — Embed Pipeline Post-Extract

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Após extract bem-sucedido, gerar embedding do texto canônico (`tool_name` + `summary` + `problem_solved`) para alimentar busca e relatórios.

## Tasks

- [x] `pipeline/embed.rs`: `run_embed_batch(db, limit)` — claim rows sem embedding
- [x] Input truncado (ex. 8k chars) — mesma política do extract
- [x] Hook opcional no fim de `run_extract` + CronJob `ai-radar-embed` em k8s
- [x] Métrica `ai_radar_embeddings_total{status}`
- [x] CLI subcommand `embed` (**T-159** workspace)

## Dependências

- **T-247** ✅ schema + provider

## Validação

- `cargo test -p ai-radar-core`
- Job manual: `kubectl create job … -- ai-radar-cli embed --limit 10`
