# T-352: agent-meter — Implement notification channels

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 4h

## Context

Tabela `notification_channels` em `migrations/20260603000008_alerts_budgets.sql:L42-50`:
```sql
notification_channels(id uuid PK, org_id FK, name, kind CHECK('slack','email','webhook'),
                       config jsonb, enabled bool, created_at)
```

Tabela `alert_history` (L52-68) tem campo `notified bool` + `payload jsonb` — pronto para dispatch.

**O `alert_service.rs:L1-4` diz explícitamente:**
> "Sem CronJob/Slack — o evaluator é exposto via endpoint manual `POST /api/alerts/evaluate`"

O `evaluate()` (L134-212) avalia rules e insere `alert_history`, mas **nunca chama canais**.
Não existe `notification_service.rs` nem Slack/webhook sender.

## Arquivos a criar/modificar

| Arquivo | Ação |
|---------|------|
| `src/services/notification_service.rs` | **CRIAR** — CRUD + dispatch engine (reqwest::Client) |
| `src/routes/notifications.rs` | **CRIAR** — REST endpoints + test dispatch |
| `src/routes/mod.rs` | Adicionar `pub mod notifications;` |
| `src/services/mod.rs` | Adicionar `pub mod notification_service;` |
| `src/app.rs` | `.merge(routes::notifications::router())` |
| `src/services/alert_service.rs` | Após `INSERT INTO alert_history` → chamar `dispatch_notification()` |
| `Cargo.toml` (collector) | Já tem `reqwest` — verificar features |

## Tasks

- [ ] Criar `notification_service.rs` com struct `NotificationChannel` (FromRow) e `NewChannel`
- [ ] Implementar `list_channels(pool, org_id)`, `create_channel(pool, new)`, `delete_channel(pool, id)`
- [ ] Implementar `dispatch(pool, channel_id, payload)` com match no `kind`:
  - `webhook`: `POST` com JSON payload para `config.url`
  - `slack`: `POST` com formatted message block para `config.webhook_url`
  - `email`: placeholder (log + TODO para integração futura)
- [ ] Criar `routes/notifications.rs`: `GET/POST /api/notifications/channels`, `DELETE /:id`, `POST /:id/test`
- [ ] Registrar em `mod.rs`, `services/mod.rs`, `app.rs`
- [ ] No `alert_service::evaluate()`: após inserir alert_history, buscar canais ativos da org e chamar dispatch
- [ ] Atualizar `alert_history.notified = true` após dispatch com sucesso
- [ ] Testar: criar canal webhook via API, disparar alert manualmente, verificar HTTP call
