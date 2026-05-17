# T-234: AI Radar — Popularity Velocity & Trend Snapshots

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

**T-233** captura snapshot pontual (stars, push). **T-234** persiste histórico por `tool_key` para calcular **velocity** (Δ stars / 7d) e tendência no score/digest.

## Tasks

- [ ] Migration: `tool_metrics_snapshots` ou JSONB history em metadata
- [ ] Collect: append snapshot idempotente por poll
- [ ] Scorer rules: `velocity_spike`, `velocity_stale`
- [ ] Métrica `ai_radar_velocity_tier_total`

## Dependências

- **T-233** ✅
