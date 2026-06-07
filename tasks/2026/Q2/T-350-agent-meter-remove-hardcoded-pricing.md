# T-350: agent-meter — Remove hardcoded pricing from HTML

- **Status**: To Do
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

- [ ] Criar struct `PlanDef { name, price_usd, features: Vec<String>, stripe_price_id }` no billing.rs
- [ ] Criar handler `GET /api/billing/plans` → retorna `[{"name":"Free","price":0,...}, ...]`
- [ ] No router de billing (L14-20): `.route("/api/billing/plans", get(plans))`
- [ ] Refatorar `pricing.html`: remover `.tier-price` hardcoded → `fetch('/api/billing/plans')` + render JS
- [ ] Remover `stub_page()` (L26-32) — substituir por redirect para `/pricing?mode=stub`
- [ ] Verificar `.preview-mock` class no HTML → remover ou substituir por screenshot real
- [ ] Testar: `curl /api/billing/plans` retorna JSON válido com 3 planos
