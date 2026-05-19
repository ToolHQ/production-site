# T-259: AI Radar — Post-Extract Embed Tail Scale

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 3h

## Context

Após cada pass de extract, o pipeline roda um “embed tail” fixo em **5** itens. Com `EMBED_BATCH_LIMIT=50` no CronJob, o tail pós-extract não acompanha — cobertura semântica fica ~50% com centenas na fila.

## Tasks

- [x] Env `POST_EXTRACT_EMBED_TAIL_LIMIT` (default 25, max 100)
- [x] Extract usa limite configurável no tail (não hardcoded 5)
- [x] Métrica/log `post_extract_embed_tail` com limite aplicado
- [x] `.env.example` + README + ConfigMap/CronJob extract

## Definition of Done

- Extract com itens novos embeda até `POST_EXTRACT_EMBED_TAIL_LIMIT` por pass
- Testes config + extract unit se aplicável
