# T-260: AI Radar — Embed Catch-Up CronJob

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 3h

## Context

CronJob `ai-radar-embed` roda 2×/h com limite 50. Para esvaziar fila de centenas de pendentes, um **catch-up** em janela separada (ex. a cada 4h, limite 100) acelera sem dobrar custo em todo extract.

## Tasks

- [ ] CronJob `ai-radar-embed-catchup` (schedule espaçado, `EMBED_BATCH_LIMIT=100` no ConfigMap ou env dedicado)
- [ ] Documentar coexistência com `ai-radar-embed` regular
- [ ] Smoke: job reduz `embeddings_pending`

## Definition of Done

- Dois CronJobs embed sem conflito (`concurrencyPolicy: Forbid` cada um)
- Runbook atualizado
