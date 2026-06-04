# T-325 — agent-meter: Span Payload Inspector

**Epic**: SaaS Revenue → Trace Visualization  
**Priority**: 🚨 Critical  
**Owner**: Copilot/VSCode  
**Est.**: 6h  
**Bloqueia**: T-326 (nesting precisará de payload armazenado)

---

## Contexto

O maior gap vs Datadog/Langfuse atual: ao clicar num span, o drawer mostra apenas
metadados (tool_name, duration, tokens, cost). Não existe preview do prompt enviado,
da resposta recebida ou da mensagem de erro. O usuário não consegue debugar "por que
esse LLM call foi lento/errou" sem sair do agent-meter.

## Schema Migration

Adicionar colunas na tabela `agent_tool_calls`:

```sql
ALTER TABLE agent_tool_calls
  ADD COLUMN IF NOT EXISTS user_prompt_preview TEXT,   -- primeiros 500 chars do prompt
  ADD COLUMN IF NOT EXISTS tool_result_preview TEXT,   -- primeiros 500 chars do resultado
  ADD COLUMN IF NOT EXISTS error_message       TEXT,   -- mensagem de erro se ok=false
  ADD COLUMN IF NOT EXISTS tool_arguments      JSONB;  -- argumentos da tool call (sem secrets)
```

## Ingest (collector/src/otlp/)

- Extrair `user_prompt_preview` do span attribute `gen_ai.prompt` / `input` / `user_prompt`
- Extrair `tool_result_preview` do span attribute `gen_ai.completion` / `output`
- Extrair `error_message` de `otel.status_description` / `exception.message`
- Extrair `tool_arguments` de `tool.arguments` / custom attributes (truncar JSONB a 2KB)
- Todos os campos são opcionais — ingest não deve falhar se ausentes

## API (conversation_service.rs)

- Incluir os 4 novos campos no `TimelineEvent` struct e na query SQL
- Truncar previews a 500 chars no SELECT (não expor prompts completos sem auth)

## Frontend (timeline.html — drawer)

Quando span selecionado, o drawer deve mostrar:

```
┌─────────────────────────────────┐
│ Event #42                       │
│ llm_chat                        │
│ claude-sonnet-4-6               │
├─────────────────────────────────┤
│ Status   ✓ ok                   │
│ Duration 4.6s                   │
│ Tokens   1.2K in / 380 out      │
│ Cost     $0.0032                │
├── User Prompt ──────────────────│
│ "Please refactor the function   │
│  handleSubmit to use async/aw…" │
├── Response Preview ─────────────│
│ "Here is the refactored versio… │
├── Tool Arguments ───────────────│
│ { "filePath": "src/app.ts",     │
│   "startLine": 42, ... }        │
└─────────────────────────────────┘
```

- Syntax highlight simples via `<pre>` com `white-space: pre-wrap`
- Botão "Copy" para cada seção
- Se `error_message` presente: mostrar em vermelho com ícone ⚠

## Acceptance Criteria

- [ ] Migration aplicada sem downtime (ADD COLUMN nullable)
- [ ] Ingest preenche campos para eventos OTLP com atributos padrão
- [ ] Drawer mostra payload preview para conversas novas
- [ ] Conversas antigas mostram "—" graciosamente (campos NULL)
- [ ] Previews truncados a 500 chars com "…" no fim
- [ ] Botão copy-payload funcional
- [ ] Zero erros console

## Notas

- NÃO armazenar prompts completos ainda (sem auth multi-tenant — T-319)
- 500 chars é suficiente para debugging; payload completo virá com T-319
- JSONB `tool_arguments` com índice GIN pode ajudar busca futura (T-316)
