# T-356: agent-meter — Stripe billing: complete integration

- **Status**: To Do
- **Priority**: 🔵 Medium
- **Owner**: Copilot/VSCode
- **Estimate**: 4h

## Context

A integração Stripe já está **bastante completa** no código:
- `stripe_service.rs:L15-65`: `create_checkout()` — cria session Stripe (retorna stub se sem key)
- `stripe_service.rs:L67-95`: `verify_webhook_signature()` — HMAC-SHA256 validação
- `stripe_service.rs:L98-180`: `record_event()` — processa 3 tipos de webhook event
- `stripe_service.rs:L183-225`: `create_portal()` — billing portal session
- `billing.rs:L40-88`: checkout handler com fallback para `price_stub_{plan}`
- `billing.rs:L135-164`: webhook handler com signature validation

**Schema pronto** (`migrations/20260603000009_auth_billing.sql`):
- `organizations.stripe_customer_id`, `stripe_subscription_id`, `plan_status`, `plan_renews_at`
- `billing_events` table para audit trail + idempotência

**O que FALTA:** provisionar as keys no Stripe Dashboard e no cluster, e testar end-to-end.

## Arquivos a modificar

| Arquivo | Ação |
|---------|------|
| K8s Secret | **CRIAR** `stripe-keys` secret no namespace `default` |
| `apps/agent-meter/k8s/agent-meter.yaml` | Adicionar env vars do Secret |
| `stripe_service.rs` | Implementar `customer.subscription.updated` → fetch plan details |
| `billing.rs` | Remover `stub_page()` (L26-32) — dead code em produção |

## Requisitos — Setup no Stripe Dashboard

> Conta criada em 07/06/2026. Falta configurar products, webhook e copiar keys.

| Env var necessária | Onde obter | Formato |
|--------------------|-----------|---------|
| `STRIPE_SECRET_KEY` | Dashboard → Developers → API Keys → Secret key | `sk_test_...` (teste) ou `sk_live_...` (prod) |
| `STRIPE_WEBHOOK_SECRET` | Dashboard → Developers → Webhooks → criar endpoint → Signing secret | `whsec_...` |
| `STRIPE_PRICE_PRO` | Dashboard → Product Catalog → criar "Pro" $29/mo recurring → Price ID | `price_...` |
| `STRIPE_PRICE_TEAM` | Dashboard → Product Catalog → criar "Team" $99/mo recurring → Price ID | `price_...` |

**Webhook endpoint URL**: `https://agent-meter.dnor.io/api/billing/webhook`

**Eventos do webhook a selecionar**:
- `checkout.session.completed`
- `customer.subscription.updated`
- `customer.subscription.deleted`
- `invoice.payment_succeeded`
- `invoice.payment_failed`

**Dica**: começar com test keys (`sk_test_...`) pra validar o fluxo antes de ir pro live.

---

## Tasks

- [ ] Criar conta/products no Stripe Dashboard:
  - Product: "agent-meter Pro" → Price: $29/mo recurring
  - Product: "agent-meter Team" → Price: $99/mo recurring
- [ ] Criar Secret no K8s: `kubectl create secret generic stripe-keys --from-literal=STRIPE_SECRET_KEY=sk_live_... --from-literal=STRIPE_WEBHOOK_SECRET=whsec_...`
- [ ] Adicionar price IDs: `STRIPE_PRICE_PRO=price_...`, `STRIPE_PRICE_TEAM=price_...`
- [ ] Montar env vars no deployment YAML do agent-meter
- [ ] Testar checkout flow: `/pricing` → select Pro → Stripe Checkout → callback → org.plan='pro'
- [ ] Testar portal: `/api/billing/portal` → Stripe Portal → cancel → org.plan='free'
- [ ] Testar webhook: `stripe trigger customer.subscription.updated` → `billing_events` registrado
- [ ] Remover `stub_page()` de `billing.rs:L26-32` e rota `/billing/stub` (L16)
- [ ] Deploy + validar em produção
