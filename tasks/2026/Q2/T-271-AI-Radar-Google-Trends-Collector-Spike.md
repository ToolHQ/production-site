# T-271: AI Radar — Google Trends Collector Spike

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Trends Google (ex.: “Claude Code”, “Cursor AI”, “local LLM”) complementam RSS — sinal de demanda, não só supply de posts.

## Tasks

- [ ] ADR: API oficial vs pytrends vs SerpAPI (ToS, rate limit, custo)
- [ ] PoC collector `source_type` novo ou `webpage` com keywords fixas
- [ ] Persistência como `raw_items` com `metadata_json.trends`
- [ ] Decisão go/no-go + estimativa T-271b (prod)

## Definition of Done

- Spike doc em `docs/AI-RADAR-DECISIONS.md` com recomendação e riscos

## Fora de escopo

- UI trends completa (fase posterior)
