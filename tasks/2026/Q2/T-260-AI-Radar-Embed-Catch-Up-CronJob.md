# T-260: AI Radar — Embed Catch-Up CronJob

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 3h

## Context

CronJob `ai-radar-embed` roda 2×/h com limite 50. Para esvaziar fila de centenas de pendentes, um **catch-up** em janela separada (ex. a cada 4h, limite 100) acelera sem dobrar custo em todo extract.

## Tasks

- [x] CronJob `ai-radar-embed-catchup` (`15 */4 * * *`, `EMBED_CATCHUP_BATCH_LIMIT=100` → env `EMBED_BATCH_LIMIT`)
- [x] Documentar coexistência com `ai-radar-embed` regular (README)
- [ ] Smoke pós-deploy: job reduz `embeddings_pending`

## Definition of Done

- Dois CronJobs embed sem conflito (`concurrencyPolicy: Forbid` cada um)
- Runbook atualizado
