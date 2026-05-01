# T-166: AI Radar — Scorer Determinístico

- **Status**: Backlog
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

- [ ] Struct `Rule { id, weight: i32, predicate: fn(&ExtractedItem) -> bool, reason: &str }` em `scorer/rules.rs`
- [ ] `RuleSet::v1()` retorna lista hardcoded das ~18 regras do roadmap (positivas e negativas)
- [ ] `Scorer::new(rules)` + `score(item) -> ScoreResult { score, decision, reasons, risks, next_step }`
- [ ] Cap do score em ±100
- [ ] `next_step` derivado da decision (template strings)
- [ ] `pipeline/score.rs::run(limit)` itera `extracted_items` sem score recente (>24h ou nunca)
- [ ] Persistir em `scores` com `scoring_version='v1'`, `reasons_json`, `risks_json`
- [ ] CLI subcommand `ai-radar score [--limit N] [--rescore-all]`
- [ ] Endpoint `POST /score/run`
- [ ] Snapshot tests com 5 ExtractedItems sintéticos cobrindo cada decisão (`adopt`/`test`/`monitor`/`ignore`)
- [ ] Property test: score ∈ [-100, 100], decision sempre dentro do enum
- [ ] Documentar regras e pesos no `apps/ai-radar/README.md`

## DoD

- Score determinístico: mesmo input → mesmo score sempre.
- 4 fixtures cobrindo cada decisão produzem decisão correta.
- Reasons explicam pontos ganhos/perdidos.
- Histórico preservado: rescoring não deleta scores antigos.
- Coverage ≥85% (regras críticas).

## Validação

```bash
cd apps/ai-radar
cargo run -p ai-radar-cli -- score --limit 20

psql $DATABASE_URL -c "SELECT decision, count(*) FROM ai_radar.scores WHERE scoring_version='v1' GROUP BY decision"
psql $DATABASE_URL -c "SELECT score, decision, reasons_json FROM ai_radar.scores ORDER BY created_at DESC LIMIT 5"

cargo test -p ai-radar-core --test scorer_deterministic
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 8 (regras detalhadas)
- Depende de: **T-165**
- Branch sugerida: `feat/T-166-ai-radar-scorer-deterministic`
