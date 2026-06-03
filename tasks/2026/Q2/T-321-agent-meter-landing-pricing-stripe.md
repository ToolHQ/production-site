# T-321: agent-meter — Landing + Pricing + Stripe Checkout

## Objetivo
Site público em `agent-meter.com` (ou subdomínio) com landing page, página de pricing, e checkout via Stripe para os planos Pro/Team. Primeira porta de entrada de receita.

## Por que (produto / monetização)
**Sem isso, não há como cobrar.** Todo o pipeline T-317–T-320 vira inútil sem um caminho do cliente até o cartão de crédito. Esta task é a etapa "passar o cartão".

## Especificações

### 1. Domínio
- Adquirir `agent-meter.com` (preferido) ou usar `agent-meter.dnor.io/landing`
- DNS via existing setup (godaddy-webhook + cert-manager)

### 2. Páginas
- `/` — Landing
  - Hero: "Observability + FinOps for your AI agents. Setup in 30 seconds."
  - Demo screenshot/loom do waterfall (T-317)
  - 3 pillars: **See** (waterfall) / **Spend** (cost attribution) / **Sleep** (alerts)
  - "Trusted by" social proof (deixar placeholder até ter clientes)
  - CTA: "Start free" + "Book demo"
- `/pricing` — Pricing
  - Free / Pro / Team / Enterprise
  - Toggle monthly/yearly (-20% yearly)
  - FAQ inline
- `/docs` — Quickstart (5min)
  - Cursor / Copilot / Claude Code / OTLP genérico
  - Ver T-323
- `/blog` — Marketing content (placeholder)
- `/changelog` — Updates públicos (gera FOMO)

### 3. Pricing inicial (a calibrar após primeiros clientes)
| Plano | Preço | Eventos/mo | Retention | Recursos |
|-------|-------|-----------|-----------|----------|
| Free | $0 | 100k | 7 dias | 1 user, 1 project, alerts básicos |
| Pro | $19/seat/mo | 1M | 30 dias | Alerts, budgets, OTel export |
| Team | $99/mo flat (5 seats) | 10M | 90 dias | SSO, RBAC, audit log, slack |
| Enterprise | Custom | Custom | Custom | On-prem, SOC2, SLA, dedicated |

### 4. Stripe integration
- Stripe Checkout (não Elements — menos código): redireciona para Stripe e volta com session_id
- Webhook `POST /webhooks/stripe`:
  - `checkout.session.completed` → ativa plan na org
  - `customer.subscription.deleted` → downgrade para free
  - `invoice.payment_failed` → email + grace period 3 dias
- Customer portal Stripe para managing billing
- Modo test inicialmente; chave live só após primeira validação E2E

### 5. Tech stack landing
- Astro ou Next.js estático (SEO friendly)
- TailwindCSS (consistente com dashboard quando possível)
- Deploy: containerized + ingress no cluster (igual aos demais)
- OG image gerada dinamicamente
- Analytics: Plausible self-hosted (sem GDPR pain) ou Posthog cloud

### 6. Conversion funnel mínimo
1. Landing → CTA "Start free"
2. Signup (T-319)
3. Onboarding wizard: nome do projeto + copiar API key + comando `curl` smoke
4. Quando smoke OK → confetti + "Upgrade to Pro" inline (não bloqueante)

## Critérios de Aceitação
- [ ] Landing live em domínio público com HTTPS
- [ ] Página `/pricing` renderiza 4 tiers
- [ ] Stripe checkout funcional em modo test
- [ ] Webhook ativa plano corretamente
- [ ] Customer portal acessível pelo `/settings/billing`
- [ ] **Browser MCP** validado: signup → checkout test card → webhook → plan ativo

## Estimativas
- Landing + pricing + docs (Astro): 6h
- Stripe integration (checkout + webhook + portal): 4h
- Onboarding wizard: 2h
- Deploy + DNS + cert: 1h
- **Total**: ~13h

## Owner
**Copilot/VSCode**

## Dependências
- Requer: T-319 (auth/orgs), T-318 (cost para mostrar nos demos), T-317 (waterfall pra screenshot)
- Habilita: primeira receita
