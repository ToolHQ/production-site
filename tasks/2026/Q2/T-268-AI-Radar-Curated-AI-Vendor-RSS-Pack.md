# T-268: AI Radar — Curated AI Vendor RSS Pack

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Substituir/subordinar feeds genéricos (HN, Lobsters) por pack **curado** de changelogs e blogs de vendors IA.

## Tasks

- [x] Script `scripts/ensure-ai-rss-sources.sh` idempotente
- [x] Feeds candidatos: OpenAI blog, Anthropic, Google AI, Hugging Face, Latent Space, etc.
- [x] Desabilitar ou rebaixar tier demo-hn / demo-lobsters após audit (T-267)
- [x] Validar collect 24h sem oversize/reject spike

## Definition of Done

- ≥8 fontes RSS tier `core` enabled; demo genéricas off ou `experimental`

## Dependências

T-267

## Entrega

- Script: `apps/ai-radar/scripts/ensure-ai-rss-sources.sh`
- Prod smoke: `collected=308`, `errors=0`, 8× tier `core` + demos disabled
- Doc: `docs/AI-RADAR-SOURCES.md` §4b
