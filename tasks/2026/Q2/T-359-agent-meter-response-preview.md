# T-359: agent-meter — Conversation response_preview population

- **Status**: To Do
- **Priority**: 🔵 Medium
- **Owner**: Copilot/VSCode
- **Estimate**: 2h

## Context

A API `/api/conversations` retorna `response_preview: null` para a maioria das conversas.

**Query atual** (`conversation_service.rs:L53`):
```sql
LEFT(MAX(tool_result) FILTER (
    WHERE tool_result IS NOT NULL
      AND LENGTH(tool_result) >= 10
      AND tool_name = 'llm_chat'
), 300) AS response_preview
```

Isso tenta extrair de `tool_result` quando `tool_name = 'llm_chat'`, mas o proxy
não gera events com `tool_name = 'llm_chat'` — ele envia como span OTLP com atributos
`gen_ai.*`. O `tool_result` é raramente populado.

**Schema atual** (`migrations/20260517000001_init.sql`):
- `agent_tool_calls.response_bytes` (integer) — existe
- `agent_tool_calls.response_sha256` (text) — existe
- `agent_tool_calls.metadata` (jsonb) — existe
- **NÃO há coluna `response_preview`** — é computado inline no SELECT

**Proxy** (`interceptor.rs`): `on_response()` lê o response body mas extrai apenas tokens/usage.
Não salva preview do conteúdo textual da resposta.

## Arquivos a modificar

| Arquivo | Ação |
|---------|------|
| `migrations/` | **CRIAR** — `ALTER TABLE agent_tool_calls ADD response_preview text` |
| `proxy/src/interceptor.rs` | No `on_response()`: extrair primeiros 300 chars do content |
| `collector/src/otlp/mod.rs` | Aceitar atributo `gen_ai.response_preview` do span |
| `collector/src/services/event_service.rs` | Salvar `response_preview` na inserção |
| `collector/src/services/conversation_service.rs` | Simplificar query — usar coluna em vez de subquery |

## Tasks

- [ ] Migration: `ALTER TABLE agent_tool_calls ADD COLUMN response_preview text`
- [ ] No `interceptor.rs` `on_response()`: extrair text content da resposta LLM (choices[0].message.content ou content[0].text), truncar a 300 chars
- [ ] Adicionar como atributo OTLP span: `gen_ai.response_preview`
- [ ] No `otlp/mod.rs`: extrair `gen_ai.response_preview` e mapear para campo na inserção
- [ ] Em `event_service.rs`: incluir `response_preview` no INSERT INTO agent_tool_calls
- [ ] Em `conversation_service.rs:L53`: simplificar query para `MAX(response_preview) FILTER(WHERE response_preview IS NOT NULL)`
- [ ] Testar: nova conversa via Copilot CLI → `curl /api/conversations` mostra response_preview não-null
