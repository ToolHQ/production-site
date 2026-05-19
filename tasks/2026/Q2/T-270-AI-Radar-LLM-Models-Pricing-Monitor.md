# T-270: AI Radar — LLM Models & Pricing Monitor

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

Mudanças de **modelos** (GPT, Claude, Gemini, open-weight) e **preços** (OpenRouter, Anthropic, OpenAI) são oportunidades operacionais — hoje não entram no radar de forma estruturada.

## Tasks

- [x] Spike OpenRouter `GET /models` (ou docs) — diff de modelos/preços
- [x] Fonte RSS/web: OpenAI, Anthropic, Google AI blog *(coberto por T-268 vendor pack)*
- [x] Schema `model_catalog_*` + eventos `model_added | model_removed | price_change`
- [x] CronJob leve (diário) + alerta quando diff > 0
- [ ] Card console “Modelos & preços” (pode ser T-275)

## Definition of Done

- Diff detectável entre duas execuções; pelo menos 1 evento persistido em smoke

## Dependências

T-269 (padrão watchlist)

## Entrega

- Migration `0008_model_catalog`
- CLI `models-sync`, CronJob `ai-radar-models-sync` (`0 6 * * *`)
- API `GET /models/catalog`, bloco `/stats.model_catalog`
- Métricas `ai_radar_model_catalog_events_*`
