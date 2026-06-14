# T-350: agent-meter — Remove hardcoded pricing from HTML

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 2h

## Context

`crates/collector/ui/pricing.html` tem os planos Free/Pro/Team com preços hardcoded
($0/$29/$99) diretamente no HTML via `.tier-price` elements.

Já existe `GET /api/cost/pricing` em `routes/cost.rs:L48` que retorna dados de `model_pricing`,
mas não há endpoint para tiers/planos de billing (Free/Pro/Team com features e preços).

O `routes/billing.rs:L22-23` serve `pricing.html` via `include_str!` (estático, compilado no binário).
O `stub_page()` em `billing.rs:L26-32` é um HTML inline placeholder.

**Config existente** (`config.rs:L19-22`): `stripe_price_pro`, `stripe_price_team` — IDs Stripe, não preços visíveis.

## Arquivos a modificar

| Arquivo | Ação |
|---------|------|
| `crates/collector/ui/pricing.html` | Tornar dinâmico — fetch `/api/billing/plans` no JS |
| `crates/collector/src/routes/billing.rs` | Adicionar `GET /api/billing/plans` no router (L14-20) |
| `crates/collector/src/config.rs` | Adicionar struct `PlanDef` com preço/features (ou tabela SQL) |
| `crates/collector/src/app.rs` | Nenhuma mudança — billing.rs já está mergeado (L35) |

## Tasks

- [x] Criar struct `PlanDef { id, name, price, price_suffix, desc, featured, annual_discount, features, cta_*, stripe_price_id }` no billing.rs
- [x] Criar handler `GET /api/billing/plans` → retorna `[{"id":"free","name":"Free","price":0,...}, ...]`
- [x] No router de billing: `.route("/api/billing/plans", get(plans))`
- [x] Refatorar `pricing.html`: remover `.tier-price` hardcoded → `fetch('/api/billing/plans')` + render JS
- [x] Remover `stub_page()` — substituído por `stub_redirect()` → `Redirect::to("/pricing?mode=stub")` + banner de stub na pricing.html
- [x] `.preview-mock` (regra CSS órfã, sem uso no HTML) → removida
- [x] Testar: `curl /api/billing/plans` retorna JSON válido (4 tiers: Free/Pro/Team/Enterprise; `stripe_price_id` vem da config)

## Notas de implementação

- Preços reais no HTML eram **$0/$19/$99/Custom** (não $0/$29/$99 como no contexto original — o HTML é a fonte da verdade).
- `PlanDef` ficou em `billing.rs` (não `config.rs`): o handler lê `state.config.stripe_price_pro/team`
  para preencher `stripe_price_id`, mantendo os IDs Stripe configuráveis por env var.
- `pricing.html`: tier cards renderizados via JS a partir de `/api/billing/plans`. Toggle mensal/anual
  recalcula preços no cliente (−20% quando `annual_discount`). Checkout usa event delegation (cobre
  hero + cards dinâmicos). ROI calculator usa o preço do Pro vindo da API.
- Stub mode: `/billing/stub` (alvo das URLs stub do `stripe_service`) redireciona para `/pricing?mode=stub`,
  que exibe um banner explicativo.
- Testes: `test_billing_plans` + `test_billing_stub_redirects` em `tests/api.rs`. Verificado também
  via `curl` em servidor local (plans 200 + JSON válido; stub 303 → `/pricing?mode=stub`).
