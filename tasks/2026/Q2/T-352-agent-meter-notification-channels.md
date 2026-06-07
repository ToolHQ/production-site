# T-352: agent-meter — Implement notification channels

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 4h

## Context

Tabela `notification_channels` existe (kind: slack/email/webhook, config jsonb, enabled) mas
não há nenhum service, nenhuma route, e alerts não usam canais para notificar.
Atualmente `alert_history` registra o disparo mas não envia nada a ninguém.

## Tasks

- [ ] Criar `services/notification_service.rs` com CRUD + dispatch
- [ ] Criar `routes/notification.rs` com `GET/POST /api/notifications/channels`, `DELETE /:id`
- [ ] Implementar dispatch para webhook (HTTP POST com payload JSON)
- [ ] Implementar dispatch para Slack (webhook URL com formatted message)
- [ ] Integrar dispatch no `alert_service::evaluate()` — após inserir `alert_history`, chamar canais ativos
- [ ] Adicionar UI na página `/alerts` para gerenciar canais
- [ ] Testes: criar canal webhook, disparar alert, verificar HTTP call
