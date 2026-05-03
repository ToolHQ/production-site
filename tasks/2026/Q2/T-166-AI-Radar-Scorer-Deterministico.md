# T-166: AI Radar — Scorer Determinístico

- **Status**: Done
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 1d
- **Opened**: 2026-05-01

## Context

Scoring reprodutível via regras versionadas (`scoring_version='v1'`), sem LLM. Garante explicabilidade: cada ponto ganho/perdido tem `reason`. Decisão final mapeada por threshold:

```
score >= 80 → adopt
score >= 60 → test
score >= 35 → monitor
score  < 35 → ignore
```

Regras inicialmente como código (sem YAML externo). Migrar para config quando precisar ajustar sem deploy.

## Tasks

- [x] Struct `Rule` + `RulePredicate` + slice estático `RULES_V1` em `scorer/rules.rs` (~20 regras roadmap)
- [x] `Scorer::v1()` + `Scorer::with_rules` (testes) sobre `RULES_V1`
- [x] `Scorer::score` → `ScoreResult { points, decision, reasons, risks, next_step, applied_rules }`
- [x] Pontos inteiros com prior **50**, soma das regras, **clamp [0, 100]** → `scores.score = points/100` (`f32` em `[0,1]`)
- [x] `next_step` por `Decision` (templates curtos)
- [x] `pipeline/score::run_score` + `extracted_items.list_pending_scoring` (24h / nunca / `--rescore-all`)
- [x] Persistência `scores` com `scoring_version='deterministic-v1'`, `reasons_json`, `risks_json`, `metadata_json`
- [x] Migração `0003_scores_history` remove `UNIQUE (extracted_item_id, scoring_version)` para histórico
- [x] CLI `score --limit --stale-hours --rescore-all`
- [x] `POST /score/run`
- [x] Testes `scorer_deterministic`: 5 fixtures (4 decisões + banda monitor) + property 800 seeds
- [x] README com thresholds, CLI/API e ponteiro para `scorer/rules.rs`

## DoD

- Score determinístico: mesmo input → mesmo score sempre.
- 4 fixtures cobrindo cada decisão produzem decisão correta.
- Reasons explicam pontos ganhos/perdidos.
- Histórico preservado: rescoring não deleta scores antigos.
- Coverage ≥85% (regras críticas) — não medido com `llvm-cov` neste slice.

## Validação

```bash
cd apps/ai-radar
cargo run -p ai-radar-cli -- score --limit 20

psql $DATABASE_URL -c "SELECT decision, count(*) FROM ai_radar.scores WHERE scoring_version='deterministic-v1' GROUP BY decision"
psql $DATABASE_URL -c "SELECT score, decision, reasons_json FROM ai_radar.scores ORDER BY created_at DESC LIMIT 5"

cargo test -p ai-radar-core --test scorer_deterministic
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 8 (regras detalhadas)
- Depende de: **T-165**
- Branch sugerida: `feat/T-166-ai-radar-scorer-deterministic`
