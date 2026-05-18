# T-255: AI Radar — Embedding Coverage Stats

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 3h

## Context

Fase 19 habilitou busca/related/duplicatas semânticos, mas o operador não vê **quantos** itens extraídos já têm vetor nem a fila pendente. Com apenas ~20 embeddings no cluster, busca e related parecem “vazios” sem diagnóstico.

## Tasks

- [x] Estender `PipelineStats` / `load_pipeline_stats` com `embeddings_total`, `embeddings_pending`, `embeddings_enabled`
- [x] Gauge Prometheus `ai_radar_embeddings_pending` (atualizado em `GET /metrics`)
- [x] Card na home do console (`/`) com cobertura % e hint de fila embed
- [x] Testes unitários para `coverage_pct`
- [x] observability/README: métrica `ai_radar_embeddings_pending`

## Definition of Done

- `GET /stats` retorna campos de embedding quando `EMBEDDINGS_ENABLED=true`
- Home mostra “X/Y itens com embedding (Z%)” ou estado desabilitado
- Métrica exposta em `/metrics` para Coroot/Grafana

## Validação

```bash
curl -fsS https://ai-radar.dnor.io/stats | jq '.embeddings_total, .embeddings_pending'
```
