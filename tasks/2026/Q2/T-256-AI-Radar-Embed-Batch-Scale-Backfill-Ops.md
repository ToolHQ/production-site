# T-256: AI Radar — Embed Batch Scale & Backfill Ops

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

CronJob `ai-radar-embed` usa `--limit 25` fixo; backfill de centenas de itens exige muitas execuções. Operadores precisam de limite configurável, job manual documentado e logs com resumo de cobertura pós-pass.

## Tasks

- [x] Env `EMBED_BATCH_LIMIT` (config + CronJob + `.env.example`)
- [x] CLI `embed` lê limite do config com override `--limit`
- [x] Default CronJob via ConfigMap `50` (teto 100 no binário)
- [x] Log estruturado `embed.coverage` com `embedded`, `pending_after`, `coverage_pct`
- [x] Runbook em README: loop de jobs manuais até `embeddings_pending=0`
- [ ] Smoke cluster: job manual reduz fila

## Definition of Done

- Um único job manual processa ≥50 itens quando há fila
- Operador sabe como esvaziar fila sem adivinhar flags
- Sem regressão em custo: limite tem teto documentado (ex. 100)

## Validação

```bash
kubectl create job ai-radar-embed-backfill --from=cronjob/ai-radar-embed -n ai-radar
kubectl logs -n ai-radar job/ai-radar-embed-backfill --tail=20
```
