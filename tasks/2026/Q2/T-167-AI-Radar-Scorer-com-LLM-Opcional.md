# T-167: AI Radar — Scorer com LLM Opcional

- **Status**: Backlog
- **Priority**: 🔽 Low
- **Epic/Owner**: AI Radar / DevExp
- **Estimation**: 4h
- **Opened**: 2026-05-01

## Context

Adiciona avaliação LLM como **segunda opinião opcional**, mesclável com o scorer determinístico via `MergePolicy::Weighted` (default 70% deterministic + 30% LLM). Modo `LLM_SCORING_ENABLED=false` desativa completamente.

Prompt do LLM scorer ancorado: "Use apenas a informação fornecida. Não invente.". Score final tem **explicabilidade completa**: ambos os scores ficam em `scores.metadata_json`.

Não permitir `LlmOnly` no MVP — sem ground truth, é arriscado.

## Tasks

- [ ] `LlmScorer::evaluate(item) -> LlmScoreOpinion { score, reasons, risks }` em `scorer/llm.rs`
- [ ] Prompt template `LLM_SCORER_PROMPT_V1` instruindo escala 0-100 + justificativas baseadas APENAS no conteúdo
- [ ] `MergePolicy` enum: `DeterministicOnly`, `Weighted { deterministic: f32, llm: f32 }`
- [ ] Default `Weighted { 0.7, 0.3 }` quando `LLM_SCORING_ENABLED=true`
- [ ] Pipeline score atualizado para chamar LLM quando flag ativa
- [ ] Persistir em `scores.metadata_json`: `{ deterministic_score, llm_score, merge_policy, llm_model }`
- [ ] Decision recalculada com score final mesclado
- [ ] Unit tests cobrindo ambas políticas
- [ ] Mock LLM scorer para testes determinísticos
- [ ] Smoke test E2E com OpenRouter real (manual, atrás de feature flag)

## DoD

- Sistema funciona com `LLM_SCORING_ENABLED=true` e `=false`.
- LLM nunca é obrigatório.
- Score final tem trilha de auditoria (deterministic + LLM separados).
- `MergePolicy` configurável por env (futuro).
- Custo LLM por item logado.
- Coverage ≥80%.

## Validação

```bash
cd apps/ai-radar
export LLM_SCORING_ENABLED=true
cargo run -p ai-radar-cli -- score --rescore-all --limit 5

psql $DATABASE_URL -c "SELECT score, decision, metadata_json->>'deterministic_score' AS det, metadata_json->>'llm_score' AS llm FROM ai_radar.scores ORDER BY created_at DESC LIMIT 5"

cargo test -p ai-radar-core --test scorer_llm
```

## References

- `docs/AI-RADAR-DECISIONS.md`
- `docs/AI-RADAR-ROADMAP.md` — Fase 9
- Depende de: **T-166** + **T-164**
- Branch sugerida: `feat/T-167-ai-radar-scorer-llm-optional`
