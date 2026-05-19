# T-268: AI Radar — Curated AI Vendor RSS Pack

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

Substituir/subordinar feeds genéricos (HN, Lobsters) por pack **curado** de changelogs e blogs de vendors IA.

## Tasks

- [ ] Script `scripts/ensure-ai-rss-sources.sh` idempotente
- [ ] Feeds candidatos: OpenAI blog, Anthropic, Google AI, Hugging Face, Latent Space, etc.
- [ ] Desabilitar ou rebaixar tier demo-hn / demo-lobsters após audit (T-267)
- [ ] Validar collect 24h sem oversize/reject spike

## Definition of Done

- ≥8 fontes RSS tier `core` enabled; demo genéricas off ou `experimental`

## Dependências

T-267
