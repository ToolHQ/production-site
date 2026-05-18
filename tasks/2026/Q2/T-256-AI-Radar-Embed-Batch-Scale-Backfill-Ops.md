# T-256: AI Radar — Embed Batch Scale & Backfill Ops

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

CronJob `ai-radar-embed` usa `--limit 25` fixo; backfill de centenas de itens exige muitas execuções. Operadores precisam de limite configurável, job manual documentado e logs com resumo de cobertura pós-pass.

## Tasks

- [ ] Env `EMBED_BATCH_LIMIT` (config + CronJob + `.env.example`)
- [ ] CLI `embed` lê limite do config com override `--limit`
- [ ] Aumentar default CronJob para 50 (ou 100) se custo OpenRouter OK
- [ ] Log estruturado `embed.coverage` com `embedded`, `pending_after`, `coverage_pct`
- [ ] Runbook em README: loop de jobs manuais até `embeddings_pending=0`
- [ ] Smoke cluster: job manual com limite alto reduz fila

## Definition of Done

- Um único job manual processa ≥50 itens quando há fila
- Operador sabe como esvaziar fila sem adivinhar flags
- Sem regressão em custo: limite tem teto documentado (ex. 100)

## Validação

```bash
kubectl create job ai-radar-embed-backfill --from=cronjob/ai-radar-embed -n ai-radar
kubectl logs -n ai-radar job/ai-radar-embed-backfill --tail=20
```
