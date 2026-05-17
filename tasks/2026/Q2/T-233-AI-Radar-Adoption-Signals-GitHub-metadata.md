# T-233: AI Radar — Adoption Signals (GitHub metadata)

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Propaga sinais de adoção GitHub (`stargazers_count`, `forks_count`, `open_issues_count`, `pushed_at`) do collect para `extracted_items.metadata_json.adoption`, alimenta regras do scorer determinístico, critério `community` no comparator e métrica `ai_radar_adoption_tier_total`.

## Tasks

- [x] Módulo `curation/adoption.rs` (tiers + snapshot)
- [x] Collector GitHub: metadata extra no `github_repo`
- [x] Extract: copiar `adoption` + `days_since_activity`
- [x] Scorer: regras `adoption_*` (+popular, +growing, +active, -dormant)
- [x] Comparator: critério `community` + activity via adoption
- [x] Métrica Prometheus `ai_radar_adoption_tier_total`
- [x] Testes `tests/adoption_scorer.rs`
- [ ] Deploy cluster + smoke

## Validação

```bash
cd apps/ai-radar && cargo test -p ai-radar-core adoption
```

Resultado: 4 testes adoption + suite core OK (2026-05-16).
