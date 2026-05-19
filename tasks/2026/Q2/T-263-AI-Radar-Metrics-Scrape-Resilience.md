# T-263: AI Radar — Metrics Scrape Resilience

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 3h

## Context

Coroot registrou ~77 `ERROR` em rajada: `metrics: embedding coverage failed` com DNS transitório (`Name or service not known`) durante rollout. Cada scrape Prometheus (15–30s) faz 2 queries Postgres síncronas — amplifica ruído e zera gauges de cobertura quando DB/DNS falha por segundos.

## Tasks

- [x] Cache TTL 60s para gauges DB-backed (`pending_raw`, `embeddings_*`)
- [x] Stale-while-revalidate: em falha, reutilizar último snapshot + `WARN`
- [x] Retry curto (2×, 100ms) em erros transitórios de pool
- [x] Testes unitários do cache; doc observability

## Definition of Done

- Rollout da API não gera dezenas de ERROR no Coroot por scrape
- `/metrics` continua 200; gauges estáveis ou stale por até TTL
