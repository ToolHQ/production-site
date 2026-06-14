# T-271: AI Radar — Google Trends Collector Spike

- **Status**: Done (implementado em T-363)
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Trends Google (ex.: “Claude Code”, “Cursor AI”, “local LLM”) complementam RSS — sinal de demanda, não só supply de posts.

## Tasks

- [x] ADR: API oficial vs pytrends vs SerpAPI (ToS, rate limit, custo) → [docs/ai-radar-trends.md](../../docs/ai-radar-trends.md)
- [x] PoC collector — `apps/ai-radar/trends-collector/` + CronJob
- [x] Persistência em `ai_radar.trend_signals`
- [x] Go prod → T-363

## Definition of Done

- Spike doc em `docs/ai-radar-trends.md` com recomendação e riscos

## Fora de escopo

- UI trends completa (fase posterior)
