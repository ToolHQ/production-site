# T-261: AI Radar — Embedding Coverage Alert

- **Status**: Backlog
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 2h

## Context

Operador só vê cobertura baixa ao abrir o console. Precisamos alerta quando `embeddings_pending` alto ou cobertura < 50% por N horas.

## Tasks

- [ ] Regra exemplo em `observability/prometheus/alerting-rules.example.yaml`
- [ ] Painel Grafana (opcional) ou doc Coroot query
- [ ] README: quando disparar backfill

## Definition of Done

- Regra documentada e testável via PromQL smoke
