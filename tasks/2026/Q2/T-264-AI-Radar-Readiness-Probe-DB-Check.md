# T-264: AI Radar — Readiness Probe DB Check

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 2h

## Context

`/health` retorna OK mesmo se Postgres estiver inacessível momentaneamente — Kubernetes envia tráfego (e scrapes pesados) para pod ainda sem DNS estável.

## Tasks

- [x] `GET /health/ready` com `SELECT 1` (timeout 2s)
- [x] `readinessProbe` no deployment apontando para `/health/ready`
- [x] `livenessProbe` mantém `/health` leve; startup também `/health/ready`
- [x] Doc rollout: readiness vs liveness

## Definition of Done

- Pod não entra no Service até DB responder

## Dependências

T-263 (métricas não devem ser readiness-critical)
