# T-355: agent-meter — Cost engine: compute_event_usd performance

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 2h

## Context

`compute_event_usd()` é PL/pgSQL IMMUTABLE (`migrations/20260603000006_cost_engine.sql:L59-100`).
Faz 2 SELECTs internos na `model_pricing` (exact match → prefix match) para **cada row**.

**Chamado inline em TODAS as queries de custo:**
- `cost_service.rs:L59` — KPI total_usd: `SUM(compute_event_usd(...))` sobre agent_tool_calls
- `cost_service.rs:L90` — by_model: mesma função agrupada
- `cost_service.rs:L122` — by_day: mesma função agrupada
- `conversation_service.rs:L59` — list_conversations: SUM por conversation
- `alert_service.rs:L220` — observe_cost: SUM na janela de tempo

**Com 14K+ rows** isso ainda roda em <200ms. Com 100K+ vai degradar.

**Heurística de tokens** (`token_estimator.rs`): `request_bytes / 4` — simplista.
LLMs usam ~3.5 chars/token (não 4 bytes). Modelos diferentes têm tokenizers diferentes.

## Solução recomendada

Opção 1 (mais simples): adicionar coluna `usd_cost numeric(12,6)` em `agent_tool_calls`,
popular na inserção via `event_service.rs`. Queries usam coluna direta em vez de função.

## Arquivos a modificar

| Arquivo | Ação |
|---------|------|
| `migrations/` | **CRIAR** nova migration: `ALTER TABLE agent_tool_calls ADD COLUMN usd_cost numeric(12,6)` |
| `src/services/event_service.rs` | Na inserção: `usd_cost = compute_event_usd(model, in, out, cached)` |
| `src/services/cost_service.rs` | Trocar `SUM(compute_event_usd(...))` por `SUM(usd_cost)` (5 queries) |
| `src/services/conversation_service.rs` | Idem — `SUM(usd_cost)` em vez de função inline |
| `src/services/alert_service.rs` | Idem |
| `src/services/token_estimator.rs` | Melhorar ratio: usar tabela de chars/token por família de modelo |

## Tasks

- [ ] `EXPLAIN ANALYZE` nas 5 queries de custo com tabela atual (14K rows) — baseline
- [ ] Criar migration: `ALTER TABLE agent_tool_calls ADD COLUMN usd_cost numeric(12,6) DEFAULT NULL`
- [ ] Backfill: `UPDATE agent_tool_calls SET usd_cost = compute_event_usd(model, estimated_input_tokens, estimated_output_tokens, cached_tokens) WHERE usd_cost IS NULL`
- [ ] Em `event_service.rs`: calcular `usd_cost` na inserção (SELECT compute_event_usd no INSERT)
- [ ] Em `cost_service.rs`: substituir 3 chamadas `SUM(compute_event_usd(...))` por `SUM(COALESCE(usd_cost,0))`
- [ ] Em `conversation_service.rs`: idem
- [ ] Em `alert_service.rs`: idem
- [ ] Melhorar `token_estimator.rs`: ratio 3.5 chars/token para modelos cl-* e gpt-*, 4.0 para outros
- [ ] Re-rodar EXPLAIN ANALYZE — comparar com baseline
