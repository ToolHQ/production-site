# T-239: agent-meter — Schema & Collector Enrichment

- **Status**: Backlog
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Est.**: 3h
- **Branch**: `feat/T-239-agent-meter-enrichment`

## Context

O agent-meter captura `execute_tool` spans do VS Code Copilot via OTLP JSON, mas perde dados
valiosos que o OpenTelemetry JS SDK já envia nos spans:

| Campo OTLP disponível | Status atual |
|---|---|
| `gen_ai.response.model` | ⚠️ só vai para `metadata` JSON, sem coluna própria |
| `gen_ai.usage.cache_read_input_tokens` | ❌ não capturado |
| `gen_ai.conversation.id` | ❌ não capturado |
| `gen_ai.request.model` | ❌ não capturado |
| `User-Agent` / `X-Forwarded-For` | ❌ não capturado (só via HTTP header) |
| Prompts / respostas | ❌ requer `captureContent: true` no VS Code |

Além disso, não existe endpoint de feed de eventos raw — só agregações. O dashboard não mostra
timestamps, modelos usados nem tokens cached por chamada.

### Schema atual (`agent_tool_calls`)
Tem `estimated_input_tokens`, `estimated_output_tokens`, `estimated_total_tokens`, `metadata` (jsonb).
Não tem colunas dedicadas para model, cached_tokens, conversation_id, client_ip, user_agent.

### Estratégia
- Adicionar colunas via migration (backward-compatible, nullable)
- Promover `model` de `metadata.model` → coluna de primeira classe (indexed)
- Capturar `User-Agent` + IP no route handler do OTLP e do `/events/tool-call`
- Novo endpoint `GET /reports/events` para feed paginado de eventos raw

## Tasks

### 1. Migration SQL
- [ ] Criar `20260517000003_enrich_tool_calls.sql`:
  ```sql
  ALTER TABLE agent_tool_calls
    ADD COLUMN IF NOT EXISTS model text,
    ADD COLUMN IF NOT EXISTS cached_tokens integer,
    ADD COLUMN IF NOT EXISTS conversation_id text,
    ADD COLUMN IF NOT EXISTS client_ip text,
    ADD COLUMN IF NOT EXISTS user_agent text;
  CREATE INDEX IF NOT EXISTS idx_agent_tool_calls_model ON agent_tool_calls(model);
  CREATE INDEX IF NOT EXISTS idx_agent_tool_calls_conversation ON agent_tool_calls(conversation_id);
  ```

### 2. Model `ToolCallEvent` (event.rs)
- [ ] Adicionar campos: `model`, `cached_tokens`, `conversation_id`, `client_ip`, `user_agent`

### 3. Collector OTLP JSON (otlp/mod.rs)
- [ ] Extrair `gen_ai.response.model` (ou `gen_ai.request.model` como fallback) → `model`
- [ ] Extrair `gen_ai.usage.cache_read_input_tokens` → `cached_tokens`
- [ ] Extrair `gen_ai.conversation.id` → `conversation_id`
- [ ] Passar `client_ip` e `user_agent` do caller (via novo parâmetro na função)

### 4. Route handler OTLP (routes/otlp.rs)
- [ ] Extrair `X-Forwarded-For` (fallback: `X-Real-IP`) → `client_ip`
- [ ] Extrair `User-Agent` → `user_agent`
- [ ] Passar para `handle_trace_request()`

### 5. Route handler events (routes/events.rs)
- [ ] Mesmo enriquecimento de IP/User-Agent no `POST /events/tool-call`

### 6. `event_service.rs` — INSERT
- [ ] Incluir novos campos no INSERT SQL
- [ ] Incluir no SELECT do record de retorno

### 7. Novo endpoint `GET /reports/events`
- [ ] Query paginada em `agent_tool_calls`:
  `event_id`, `tool_name`, `model`, `started_at`, `duration_ms`, `ok`,
  `estimated_input_tokens`, `estimated_output_tokens`, `cached_tokens`,
  `agent`, `ide`, `mcp_server`, `conversation_id`, `client_ip`
- [ ] Params: `from`, `to`, `ide`, `agent`, `model`, `conversation_id`, `limit` (default 50), `offset`
- [ ] Registrar rota em `routes/mod.rs`

### 8. `top_tools` enriquecido
- [ ] Adicionar coluna `top_model` (moda do model no grupo) ao `TopTool` struct
- [ ] Adicionar `cached_tokens_total` ao retorno
- [ ] Adicionar `avg_input_tokens` e `avg_output_tokens` separados

### 9. Build + migration no cluster
- [ ] `cargo check` limpo
- [ ] Rodar migration no postgres do cluster via `kubectl exec`
- [ ] Build + push + deploy via `./deploy.sh`
- [ ] Testar `GET /reports/events` via curl

## Acceptance Criteria
- `GET /reports/events` retorna lista com `model`, `cached_tokens`, `started_at`, `client_ip`
- Span do VS Code Copilot grava `model` na coluna dedicada (verificar com `psql`)
- `top_tools` resposta inclui `top_model` e `cached_tokens_total`
- `cargo check` sem erros ou warnings novos
