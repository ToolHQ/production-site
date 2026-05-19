# T-273: AI Radar — Collect Relevance Gate

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 5h

## Context

Mesmo com feeds melhores, entradas off-topic consomem LLM extract/score. Gate **antes** do extract reduz ruído e custo.

## Tasks

- [ ] Heurísticas: keywords IA/agents/K8s/self-hosted no title+body
- [ ] Penalizar domínios genéricos sem match
- [ ] `raw_items.status = skipped` + reason `low_relevance` + métrica
- [ ] Override por `source.tier = core` (sempre passa)
- [ ] Testes unitários + amostra prod

## Definition of Done

- Collect→extract ratio melhora; menos itens “aleatórios” no Explorer

## Dependências

T-267, T-268
