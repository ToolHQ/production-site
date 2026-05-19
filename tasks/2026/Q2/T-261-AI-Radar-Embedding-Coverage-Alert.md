# T-261: AI Radar — Embedding Coverage Alert

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 2h

## Context

Operador só vê cobertura baixa ao abrir o console. Precisamos alerta quando `embeddings_pending` alto ou cobertura < 50% por N horas.

## Tasks

- [x] Gauge `ai_radar_embeddings_coverage_pct` no scrape `/metrics`
- [x] Regras em `observability/prometheus/alerting-rules.example.yaml`
- [x] Painéis Grafana + queries Coroot em `observability/README.md`
- [x] README: quando disparar backfill

## Definition of Done

- Regra documentada e testável via PromQL smoke
