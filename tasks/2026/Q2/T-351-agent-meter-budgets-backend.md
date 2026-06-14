# T-351: agent-meter — Implement budgets backend

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 4h

## Context

Tabela `budgets` criada em `migrations/20260603000008_alerts_budgets.sql:L20-40` com schema completo:
```sql
budgets(id uuid PK, org_id FK, name, period CHECK('daily','weekly','monthly'),
        amount_usd numeric(12,2), soft_threshold_pct, hard_threshold_pct,
        hard_cap bool, filters jsonb, enabled bool, created_at)
```

**Zero código backend existe.** Não há `budget_service.rs`, não há rotas, não há avaliação.
O `alert_service.rs:L148` suporta rule_types `cost_spike|error_rate|latency_p95|token_burn|tool_failure`
mas não tem `budget_breach`.

**Router** (`app.rs:L23-42`): `billing`, `alerts`, `cost` já estão mergeados. Budget é novo.
**Services** (`services/mod.rs`): 10 módulos — precisa adicionar `budget_service`.

## Arquivos a criar/modificar

| Arquivo | Ação |
|---------|------|
| `src/services/budget_service.rs` | **CRIAR** — CRUD + avaliação de threshold |
| `src/routes/budgets.rs` | **CRIAR** — REST endpoints |
| `src/routes/mod.rs` | Adicionar `pub mod budgets;` (L15+) |
| `src/services/mod.rs` | Adicionar `pub mod budget_service;` (L10+) |
| `src/app.rs` | `.merge(routes::budgets::router())` (L42+) |
| `src/services/alert_service.rs` | Integrar budget check no `evaluate()` (L148+) |

## Tasks

- [ ] Criar `budget_service.rs` com structs `Budget`, `NewBudget` derivando `sqlx::FromRow` + `Serialize`
- [ ] Implementar `list_budgets(pool, org_id)`, `create_budget(pool, new)`, `delete_budget(pool, id)`
- [ ] Implementar `evaluate_budgets(pool)`: para cada budget enabled, SUM(compute_event_usd) no período vs threshold
- [ ] Criar `routes/budgets.rs` com router: `GET /api/budgets` (list), `POST /api/budgets` (create), `DELETE /api/budgets/:id`
- [ ] Registrar mod + router em `mod.rs` e `app.rs`
- [ ] Integrar no `alert_service::evaluate()`: após avaliar rules, chamar `evaluate_budgets()`
- [ ] Testar: criar budget via API, verificar avaliação contra dados reais
