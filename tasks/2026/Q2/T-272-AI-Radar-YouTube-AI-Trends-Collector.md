# T-272: AI Radar — YouTube AI Trends Collector

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 6h

## Context

YouTube concentra reviews, tutoriais e hype de ferramentas IA. `source_type=youtube` existe no schema mas não está operacional em prod.

## Tasks

- [ ] Spike YouTube Data API v3 (quota, API key secret)
- [ ] Lista canais/keywords: AI coding, local LLM, K8s AI
- [ ] Implementar collector mínimo → `raw_items`
- [ ] Extract prompt ajustado para vídeo (title + description)
- [ ] CronJob + runbook quota

## Definition of Done

- 1 fonte YouTube enabled; collect smoke OK

## Dependências

T-267, decisão API key (secret `ai-radar-youtube`)
