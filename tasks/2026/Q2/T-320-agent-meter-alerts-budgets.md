# T-320: agent-meter — Alerts & Budgets

## Objetivo
Sistema de alertas (cost spike, error rate, latency p95) e **budgets** com hard/soft caps para custos. Justifica recurring revenue: "monitoring que te avisa antes de explodir o bill da OpenAI".

## Por que (produto / monetização)
- "$29/mo para nunca mais ter um susto de $500 na fatura" — pitch direto.
- Budget alerts são feature paga padrão em FinOps tools (Vantage, CloudZero).
- Habilita storytelling de ROI imediato.

## Especificações

### 1. Tipos de alertas
| Tipo | Trigger | Default channel |
|------|---------|-----------------|
| Cost spike | cost(1h) > N × avg(7d, mesma hora) | email |
| Budget threshold | spent_mtd > X% do budget | email + slack |
| Error rate | error_count(15min) / total > 5% | slack |
| Latency p95 | p95(duration_ms, 15min) > N ms | slack |
| Token blow-up | tokens_in > N por evento | email |

### 2. Schema
```sql
CREATE TABLE budgets (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL,
  amount_usd NUMERIC(10,2) NOT NULL,
  period VARCHAR(16) NOT NULL,  -- monthly|weekly|daily
  hard_cap BOOLEAN DEFAULT FALSE,  -- se true, rejeita ingest após estourar (Pro+)
  notify_at_pct INTEGER[] DEFAULT '{50,80,100}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE alert_rules (
  id UUID PRIMARY KEY,
  project_id UUID NOT NULL,
  type VARCHAR(32) NOT NULL,
  config JSONB NOT NULL,        -- thresholds, windows
  channels VARCHAR(32)[] NOT NULL,  -- email|slack|webhook|pagerduty
  enabled BOOLEAN DEFAULT TRUE
);

CREATE TABLE alert_events (
  id UUID PRIMARY KEY,
  rule_id UUID NOT NULL,
  fired_at TIMESTAMPTZ NOT NULL,
  resolved_at TIMESTAMPTZ,
  context JSONB
);

CREATE TABLE notification_channels (
  id UUID PRIMARY KEY,
  org_id UUID NOT NULL,
  type VARCHAR(32) NOT NULL,    -- email|slack|webhook
  config JSONB NOT NULL          -- url, secret, etc
);
```

### 3. Engine
- CronJob `alert-evaluator` a cada 1min: avalia regras ativas, dispara notifications, registra em `alert_events`
- Deduplicação: não re-disparar regra ativa se já firing (resolve quando volta abaixo do threshold)
- Slack: webhook URL com payload markdown
- Email: SMTP via Postfix interno ou Resend/SES (conforme T-322)

### 4. UI
- `/alerts` — lista de regras + histórico, mute/snooze
- `/budgets` — definir budget mensal por projeto, gauge de burn
- Banner global no topo se há alertas firing
- Botão "Test alert" envia notificação dummy

### 5. Hard cap (Team+ feature)
- Quando `hard_cap=true` e `spent_mtd >= amount_usd`:
  - Ingest retorna 429 com `x-rate-limit-reason: budget_exceeded`
  - Email automático para owners da org
  - Botão "Override" libera por 24h

## Critérios de Aceitação
- [ ] Cost spike alert dispara em conversa real
- [ ] Slack/email recebem notificação
- [ ] Budget gauge renderiza burn rate corretamente
- [ ] Hard cap bloqueia ingest e libera com override
- [ ] **Browser MCP** validado: criar regra → forçar trigger → ver no histórico

## Estimativas
- Schema: 1h
- Engine evaluator (CronJob): 3h
- Notification channels (slack, email, webhook): 2h
- UI: 3h
- Hard cap: 1h
- **Total**: ~10h

## Owner
**Copilot/VSCode**

## Dependências
- Requer: T-318 (cost data), T-319 (multi-tenant para org-scoped)
- Habilita: tier Pro+ pricing
