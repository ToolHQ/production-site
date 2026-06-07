# T-356: agent-meter — Stripe billing: complete integration

- **Status**: To Do
- **Priority**: 🔵 Medium
- **Owner**: Copilot/VSCode
- **Estimate**: 4h

## Context

Billing tem 3 stubs que retornam URLs fake (`/billing/stub?price=...`) quando `STRIPE_SECRET_KEY`
não está configurado. A página billing/stub é um HTML inline placeholder.
O webhook handler (`/api/billing/webhook`) existe mas `STRIPE_WEBHOOK_SECRET` precisa ser configurado.

Stripe Keys precisam ser provisionadas e o fluxo testado end-to-end.

## Tasks

- [ ] Criar Secret `stripe-keys` no K8s com `STRIPE_SECRET_KEY` e `STRIPE_WEBHOOK_SECRET`
- [ ] Montar env vars no deployment do agent-meter
- [ ] Criar products/prices no Stripe Dashboard (Free, Pro $29, Team $99)
- [ ] Mapear price IDs no config (env var ou tabela)
- [ ] Testar checkout flow: pricing → Stripe → callback → org.plan atualizado
- [ ] Testar portal flow: manage subscription → cancel/upgrade
- [ ] Testar webhook: `customer.subscription.updated` → atualiza org
- [ ] Remover billing/stub page e fallback URLs
