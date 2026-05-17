# T-242: AI Radar — Explorer Item Signal Panel

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

O Explorer (**T-177**, **T-235**) mostra badges na lista, mas o **drill-down** (`#/items/:id`) não consolida os metadados da Fase 17. O operador precisa abrir JSON ou cruzar fontes manualmente.

**Objetivo:** painel “Sinais” no detalhe do item:

- Adoption: stars, forks, tier, `stars_delta_7d`
- Velocity: `velocity_tier`, regras `velocity_spike` / `velocity_stale`
- Qualidade extract: `quality_warn` / gate (**T-232**)
- Fonte: tier de saúde da `source_id` (cache ou join leve)
- Calibração: delta de pontos e `feedback_calibration` se presente

## Tasks

- [ ] Enriquecer `GET /items/:id` (ou reutilizar `metadata_json` já retornado) com bloco `signals` tipado
- [ ] UI: card/grid no detalhe; badges com cores do design system (**T-203**)
- [ ] Link “Comparar categoria” → prepara **T-245**
- [ ] Smoke manual no console

## Dependências

- **T-235** ✅ lista/badges
- **T-234**, **T-233**, **T-238**, **T-236** ✅ metadata no score/extract

## Validação

- Abrir item com GitHub raw → ver stars + velocity
- `cargo test -p ai-radar-api` se houver teste de serialização
