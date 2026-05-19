# T-277 — Agent Meter: Top Tasks Vazio — Reconversão para "Top Conversations"

**Status**: 🆕 Backlog  
**Priority**: 🔼 High  
**Owner**: Copilot/VSCode  
**Area**: agent-meter / backend + frontend  
**Estimated Effort**: M (2–4h)

---

## Problema

A aba "Top Tasks" nunca exibe dados. Sempre mostra "No data yet".

### Root Cause (confirmada por auditoria)

O campo `task_id` em `agent_tool_calls` é **sempre `NULL`** para eventos vindos por OTLP.
No código de ingestion (`otlp/mod.rs`), todos os paths de parse hardcodam:

```rust
task_id: None,
skill: None,
```

A query `top-tasks` filtra `WHERE task_id IS NOT NULL`, então retorna zero linhas.

### Por que task_id nunca é populado?

- A API REST `/tasks/start` e `/tasks/end` existem mas nenhum agente as integra atualmente
- OTLP spans de agentes (Copilot, Cursor, Antigravity) não carregam atributo de `task_id`
- O campo `skill` sofre do mesmo problema

---

## Solução Proposta

### Opção A — Reconversão para "Top Conversations" (recomendada)

Renomear a feature para agrupar por `conversation_id` em vez de `task_id`.
O `conversation_id` **já é populado** por OTLP e contém dados reais.

**Mudanças:**

1. **Backend** (`report_service.rs`): Criar/modificar a query de top_tasks para usar `conversation_id`:
   ```sql
   SELECT
       conversation_id as task_id,
       COUNT(*)::bigint as tool_calls,
       SUM(estimated_total_tokens)::bigint as total_estimated_tokens,
       SUM(duration_ms)::bigint as total_duration_ms,
       COUNT(*) FILTER (WHERE not ok)::bigint as errors,
       COUNT(DISTINCT tool_name)::bigint as distinct_tools
   FROM agent_tool_calls
   WHERE conversation_id IS NOT NULL
   ```

2. **Frontend** (`dashboard.html`):
   - Renomear tab button: "Top Tasks" → "Top Conversations"
   - Renomear coluna "Task ID" → "Conv ID" (com `data-tab="tasks"` mantido para não quebrar state)
   - Coluna Conv ID: adicionar link de click-to-filter igual ao Events tab

### Opção B — Instrumentação de task_id via OTLP (longo prazo)

Adicionar atributo `agent.task_id` nos spans de cada agente.
Requer mudanças em todos os SDKs de instrumentação (Copilot extension, Cursor, etc.).
Melhor solução a longo prazo; pode coexistir com Opção A.

**Recomendação**: Implementar Opção A agora. Opção B é roadmap futuro.

---

## Arquivos a Modificar

1. `apps/agent-meter/crates/collector/src/services/report_service.rs`
   - Função `top_tasks()` → mudar `WHERE task_id IS NOT NULL` para `conversation_id IS NOT NULL` e agrupar por `conversation_id`

2. `apps/agent-meter/crates/collector/ui/dashboard.html`
   - Tab label: "Top Tasks" → "Top Conversations"
   - Coluna header: "Task ID" → "Conv ID"
   - Adicionar click-to-filter em Conv ID cells (igual ao Events tab)

---

## Critérios de Aceite

- [ ] Tab "Top Conversations" mostra dados reais (agrupados por conversation_id)
- [ ] Colunas: Conv ID, Tool Calls, Total Tokens, Total Duration, Errors, Distinct Tools
- [ ] Click em Conv ID abre Events tab filtrado por aquela conversa
- [ ] Funciona com filtros de tempo e IDE/agent globais
- [ ] Deploy + smoke test confirmado

---

## Contexto Adicional

- Auditoria realizada em 2025-07-14
- Campo `conversation_id` está populado corretamente: confirmado em Events tab (a0870cbd-fba3-46f0-b5ac-d4e5f3f82598)
- Dados do cluster 6h: ~90 tool calls de 1 conversation ID principal (sessão atual Copilot)
