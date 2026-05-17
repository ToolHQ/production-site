# T-244: AI Radar — Explorer Filters Velocity & Health

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Cursor / AI Radar
- **Estimation**: 4h

## Context

**T-235** adicionou sort por adoption/score. Faltam **filtros** por sinais da Fase 17 para reduzir ruído na fila de revisão:

- `velocity_tier` (hot / warm / stale / unknown)
- `quality_warn` (extract gate)
- `source_health_tier` (healthy / degraded / noisy) — via join ou denormalização leve em listagem

## Tasks

- [ ] `GET /items`: query params `velocity_tier`, `quality_warn`, `source_health` (validar combinação com `decision`, `category`)
- [ ] Índices SQL se explain mostrar seq scan (só se necessário)
- [ ] UI: chips/selects no Explorer; persistir em hash `?velocity=hot`
- [ ] Testes repositório + 1 teste API

## Dependências

- **T-234**, **T-232**, **T-238** ✅

## Validação

- Filtrar `velocity_tier=hot` e conferir contagem vs Prometheus `ai_radar_velocity_tier_total`
