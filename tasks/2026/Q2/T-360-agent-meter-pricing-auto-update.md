# T-360: agent-meter — Pricing auto-update from provider APIs

- **Status**: To Do
- **Priority**: 🟢 Low
- **Owner**: Copilot/VSCode
- **Estimate**: 4h

## Context

A tabela `model_pricing` é populada por migration SQL manualmente.
Quando providers atualizam preços, o DB fica defasado até alguém rodar uma migration.

**Schema existente** (`migrations/20260603000006_cost_engine.sql:L1-30`):
```sql
model_pricing(id bigserial PK, model text, match_kind text,
              input_per_mtok numeric, output_per_mtok numeric, cached_per_mtok numeric,
              priority int, source text, notes text, created_at, updated_at)
```

O campo `source` já suporta: 'manual', 'anthropic', 'openai', 'google', 'xai', 'deepseek', 'meta'.
O `UNIQUE INDEX (model, match_kind)` permite `ON CONFLICT DO UPDATE` seguro.

**Endpoint existente** (`routes/cost.rs:L48`): `GET /api/cost/pricing` — lista todos.
**Último update manual**: migration `20260607000012` (GPT-5.x pricing).

## Arquivos a criar/modificar

| Arquivo | Ação |
|---------|------|
| `src/services/pricing_sync_service.rs` | **CRIAR** — fetch + parse + UPSERT |
| `src/routes/admin.rs` | **CRIAR** — `POST /api/admin/pricing/sync` |
| `src/routes/mod.rs` | `pub mod admin;` |
| `src/services/mod.rs` | `pub mod pricing_sync_service;` |
| `src/app.rs` | `.merge(routes::admin::router())` |
| `migrations/` | `ALTER TABLE model_pricing ADD last_verified_at timestamptz` |
| `k8s/` | Opcional: CronJob YAML para sync semanal |

## Tasks

- [ ] Migration: `ALTER TABLE model_pricing ADD COLUMN last_verified_at timestamptz`
- [ ] Criar `pricing_sync_service.rs` com `sync_from_provider(pool, provider)`:
  - `openai`: GET `https://openai.com/api/pricing/` → parse HTML/JSON → extract model + price
  - `anthropic`: GET `https://docs.anthropic.com/en/docs/about-claude/models` → parse
  - `google`: GET `https://ai.google.dev/pricing` → parse
- [ ] UPSERT: `INSERT INTO model_pricing ... ON CONFLICT (model, match_kind) DO UPDATE SET input_per_mtok=EXCLUDED..., last_verified_at=now()`
- [ ] Log mudanças: se preço mudou, logar `tracing::info!("price changed: {} {} -> {}", model, old, new)`
- [ ] Criar `routes/admin.rs`: `POST /api/admin/pricing/sync` → chama sync_from_provider para todos os providers
- [ ] Retornar JSON com `{synced: N, updated: N, errors: [...]}`
- [ ] Registrar em mod.rs + services/mod.rs + app.rs
- [ ] Opcional: CronJob K8s que faz `curl -X POST http://agent-meter:8081/api/admin/pricing/sync` semanalmente
- [ ] Testar: `curl -X POST /api/admin/pricing/sync` → retorna resultado + verificar model_pricing atualizado
