# T-357: agent-meter — Pricing model: add AI Credits concept

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 3h

## Context

O Copilot CLI e Cursor Pro cobram por **subscription** (créditos/premium requests), não por token.
O dashboard mostra custo em USD baseado no preço de API direto, mas para Copilot o custo real
é zero (incluso no plano GitHub) ou em "AI Premium Requests" do plano.

**Schema existente:**
- `model_pricing` (`migrations/20260603000006_cost_engine.sql:L1-30`): colunas `input_per_mtok`, `output_per_mtok`, `source`
- `organizations.plan` (`migrations/20260603000007_multitenant.sql:L8-13`): CHECK('free','pro','team','enterprise')
- `compute_event_usd()` calcula sempre em USD — sem noção de créditos

**Queries afetadas** (todas em `cost_service.rs`):
- KPIs (L59): `SUM(compute_event_usd(...))` → precisa separar USD vs credits
- by_model (L90): agrupamento por modelo → adicionar coluna `billing_model`
- by_day (L122): idem

**IDE tracking** já funciona: `agent_tool_calls.ide` captura 'vscode'/'cursor'/'jetbrains' etc.

## Arquivos a modificar

| Arquivo | Ação |
|---------|------|
| `migrations/` | **CRIAR** — `ALTER TABLE model_pricing ADD billing_model text DEFAULT 'token', ADD credits_per_request numeric` |
| `src/services/cost_service.rs` | Separar `total_usd` vs `total_credits` nos KPIs |
| `src/routes/cost.rs` | Retornar `credits` no JSON response |
| `ui/cost.html` | Adicionar tab/seção "AI Credits" com breakdown por IDE |
| `ui/dashboard.html` | KPI card: "API Cost" + "Credits Used" separados |

## Tasks

- [ ] Migration: `ALTER TABLE model_pricing ADD COLUMN billing_model text NOT NULL DEFAULT 'token' CHECK(billing_model IN ('token','credit','subscription'))`
- [ ] Migration: `ALTER TABLE model_pricing ADD COLUMN credits_per_request numeric(8,2) DEFAULT NULL`
- [ ] UPDATE model_pricing para modelos copilot/cursor: `SET billing_model='subscription', credits_per_request=1`
- [ ] Em `cost_service.rs`: separar query KPI — `SUM(CASE WHEN billing_model='token' THEN compute_event_usd(...) END) AS total_usd` + `SUM(CASE WHEN billing_model!='token' THEN credits_per_request END) AS total_credits`
- [ ] Atualizar struct `CostKpis` (L11-22): adicionar `total_credits: f64`
- [ ] Atualizar `CostSummary` com `by_billing_model` breakdown
- [ ] Em `cost.html`: tab "USD" (padrão) + tab "Credits" com chart separado
- [ ] Em `dashboard.html`: KPI card duplo "API Cost: $X.XX" + "Credits: N used"
- [ ] Documentar na docs page: "Token billing vs Subscription billing"
- [ ] Testar: conversa Copilot → aparece em Credits, não em USD
