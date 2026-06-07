# T-351: agent-meter — Implement budgets backend

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 4h

## Context

A tabela `budgets` foi criada na migration `20260603000008_alerts_budgets.sql` com campos completos
(org_id, name, period, amount_usd, soft/hard thresholds, filters, enabled), mas **zero código backend** existe.
Nenhum service, nenhuma route, nenhuma avaliação. Feature fantasma.

## Tasks

- [ ] Criar `services/budget_service.rs` com CRUD: list, create, update, delete
- [ ] Criar `routes/budget.rs` com endpoints: `GET/POST /api/budgets`, `PUT/DELETE /api/budgets/:id`
- [ ] Implementar avaliação de budget: comparar gasto acumulado (via `compute_event_usd`) vs threshold
- [ ] Integrar avaliação no cron de alerts (`evaluate`) — disparar alert quando soft/hard threshold atingido
- [ ] Adicionar página `budgets.html` ou seção na página `/cost`
- [ ] Testes: criar budget, simular gasto, verificar disparo de alert
