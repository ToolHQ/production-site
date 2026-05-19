# T-270: AI Radar — LLM Models & Pricing Monitor

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

Mudanças de **modelos** (GPT, Claude, Gemini, open-weight) e **preços** (OpenRouter, Anthropic, OpenAI) são oportunidades operacionais — hoje não entram no radar de forma estruturada.

## Tasks

- [ ] Spike OpenRouter `GET /models` (ou docs) — diff de modelos/preços
- [ ] Fonte RSS/web: OpenAI, Anthropic, Google AI blog
- [ ] Schema `model_snapshots` ou metadata em `raw_items` (`event_type: model_release | price_change`)
- [ ] CronJob leve (diário) + alerta quando diff > 0
- [ ] Card console “Modelos & preços” (pode ser T-275)

## Definition of Done

- Diff detectável entre duas execuções; pelo menos 1 evento persistido em smoke

## Dependências

T-269 (padrão watchlist)
