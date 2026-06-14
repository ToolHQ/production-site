# agent-meter — Telemetry Coverage Matrix

> Última atualização: 2026-06-06
> Objetivo: **100% de cobertura** para todas as fontes de telemetria suportadas.

---

## 📊 Matrix de Cobertura por Fonte

| Campo DB (`agent_tool_calls`) | VS Code (OTLP nativo) | Eclipse (mitmproxy) | Copilot CLI (mitmproxy) | MCP-wrapper |
|-------------------------------|:---:|:---:|:---:|:---:|
| **model** | ✅ | ✅ | ✅ | ❌ (N/A) |
| **estimated_input_tokens** | ✅ | ✅ | ✅ | ❌ (N/A) |
| **estimated_output_tokens** | ✅ | ✅ | ✅ | ❌ (N/A) |
| **cached_tokens** | ✅ | ✅ | ✅ | ❌ (N/A) |
| **reasoning_tokens** | ✅ | ✅ | ✅ | ❌ (N/A) |
| **user_prompt** | ✅ | ✅ (`<userRequest>`) | ✅ | ❌ (N/A) |
| **tool_arguments** | ✅ | ✅ | ✅ | ✅ |
| **tool_result** | ✅ | ✅ (correlação call_id) | ✅ (correlação call_id) | ✅ |
| **response_text** (LLM output) | ✅ ¹ | ✅ | ✅ | ❌ (N/A) |
| **conversation_id** | ✅ | ✅ (session_id) | ✅ (session_id) | ❌ ² |
| **tool_name** | ✅ | ✅ | ✅ | ✅ |
| **mcp_server** | ✅ (inferido) | ✅ (vscode-builtin) | ✅ (vscode-builtin) | ✅ (env) |
| **duration_ms** | ✅ | ✅ | ✅ | ✅ |
| **ok / error** | ✅ | ✅ | ✅ | ✅ |
| **finish_reason** | ✅ | ✅ | ✅ | ❌ (N/A) |
| **trace_id / span_id** | ✅ | ✅ | ✅ | ❌ |
| **parent_span_id** | ✅ | ✅ | ✅ | ❌ |
| **tool_call_id** | ✅ | ✅ (call_id) | ✅ (call_id) | ✅ (jsonrpc id) |
| **ide** | ✅ (auto) | ✅ (auto: "copilot-eclipse") | ✅ (auto: "copilot-cli") | ⚠️ (env) |
| **agent** | ✅ | ❌ ³ | ❌ ³ | ⚠️ (env) |
| **repo / branch** | ❌ ⁴ | ❌ | ❌ | ⚠️ (env) |
| **task_id** | ❌ | ❌ | ❌ | ⚠️ (env) |
| **request_bytes** | ✅ | ✅ | ✅ | ✅ |
| **response_bytes** | ✅ | ✅ | ✅ | ✅ |
| **request_max_tokens** | ✅ | ✅ | ✅ | ❌ |
| **request_temperature** | ✅ | ✅ | ✅ | ❌ |
| **llm_system** | ✅ | ✅ | ✅ | ❌ |

### Legenda
- ✅ = capturado automaticamente
- ⚠️ = parcialmente implementado ou via env var
- ❌ = não capturado
- ❌ (N/A) = não aplicável para essa fonte

---

## 🔧 Fontes de Telemetria — Arquitetura

### 1. VS Code (OTLP Nativo)

- **Mecanismo**: OTLP JSON/Protobuf via `POST /v1/traces` (porta 4318)
- **Config**: `github.copilot.chat.otel.endpoint = http://localhost:4318`
- **Content**: `github.copilot.chat.otel.captureContent = true` (envia prompts/responses)
- **Proxy**: Não necessário — OTLP built-in no Copilot extension
- **Port-forward**: `kubectl port-forward svc/agent-meter 4318:4318`
- **IDE Detection**: `service.name` contém "copilot" ou "vscode"
- **Cobertura**: **96%** (falta apenas repo/branch/task_id/agent — impossível sem env vars)

### 2. Eclipse (mitmproxy Interceptor)

- **Mecanismo**: mitmproxy addon intercepta HTTPS para `api.githubcopilot.com`
- **Arquivo**: [`apps/agent-meter/eclipse-proxy/copilot_interceptor.py`](../apps/agent-meter/eclipse-proxy/copilot_interceptor.py)
- **Proxy**: `mitmdump -p 8899 -s copilot_interceptor.py` (WSL, porta 8899)
- **API**: OpenAI Responses API (SSE streaming `text/event-stream`)
- **SSE Parsing**: Extrai `response.completed` event com usage + output
- **Features**: Correlação cross-request de tool results via `call_id`, parent-child span linking
- **IDE Detection**: `service.name = "eclipse-copilot"`
- **Cobertura**: **96%** (falta apenas repo/branch/task_id/agent — impossível sem env vars)

### 3. Copilot CLI (mitmproxy — mesmo interceptor)

- **Mecanismo**: Mesmo `copilot_interceptor.py` via `HTTPS_PROXY=http://localhost:8899`
- **Wrapper**: [`apps/agent-meter/eclipse-proxy/copilot-cli-metered.sh`](../apps/agent-meter/eclipse-proxy/copilot-cli-metered.sh)
- **API**: OpenAI Responses API (SSE streaming) — modelo `gpt-5.4`
- **Setup**: `HTTPS_PROXY=http://127.0.0.1:8899 SSL_CERT_FILE=~/.mitmproxy/mitmproxy-ca-cert.pem gh copilot -p "..."`
- **IDE Detection**: Auto-detect via User-Agent "copilot-cli"
- **Validado**: 2026-06-06 — interceptação completa (tokens, tool_calls, skills, results)
- **Cobertura**: **96%** (mesmos gaps que Eclipse)

### 4. MCP-wrapper (Rust Proxy)

- **Mecanismo**: Proxy JSON-RPC transparente entre IDE ↔ MCP server
- **Arquivo**: [`apps/agent-meter/crates/mcp-wrapper/src/proxy.rs`](../apps/agent-meter/crates/mcp-wrapper/src/proxy.rs)
- **Deploy**: K8s pod ou sidecar
- **Captura**: `tools/call` arguments + result, `tools/list`, `initialize`
- **Limitação**: Não captura LLM context (tokens, model) — only MCP tool I/O
- **Cobertura**: **100%** (para o scope MCP — não é LLM)

---

## 📝 Notas

1. **VS Code com captureContent=true**: Envia prompts e responses completos via OTLP (habilitado 2026-06-06).
2. **MCP-wrapper sem conversation_id**: Cada tool call é independente, sem agrupamento em conversas.
3. **Agent detection**: Poderia inferir "copilot" do header `copilot-integration-id` — low priority.
4. **Repo/branch**: Nenhuma fonte envia automaticamente — requer enriquecimento via env vars ou header injection.

---

## 🎯 Gaps Restantes (todos low-priority)

| Gap | Fontes afetadas | Solução possível |
|-----|-----------------|------------------|
| `agent` | Eclipse, CLI | Inferir "copilot" do header `copilot-integration-id` |
| `repo / branch` | Todas | Env var injection no proxy ou resource attribute OTLP |
| `task_id` | Todas | Correlação com tasks ativas no agent-meter |

---

## 📈 Score de Cobertura

| Fonte | Campos Preenchidos | Total Campos | Score |
|-------|:--:|:--:|:--:|
| VS Code (OTLP) | 24/27 | 27 | **89%** |
| Eclipse (mitmproxy) | 24/27 | 27 | **89%** |
| Copilot CLI (mitmproxy) | 24/27 | 27 | **89%** |
| MCP-wrapper | 10/27 | 27 | **37%** (scope limitado a MCP) |

**Campos impossíveis de fechar automaticamente** (3/27): `agent`, `repo/branch`, `task_id` — requerem enrichment manual ou env vars.

**Cobertura funcional efetiva** (excluindo campos de contexto externo): **96%** para todas as fontes LLM.

---

## 🕐 Histórico

| Data | Mudança |
|------|---------|
| 2026-06-06 | Criação do doc. Eclipse 100%: request_bytes, response_bytes, max_tokens, temperature, llm_system, parent_span_id, cached_tokens, reasoning_tokens, finish_reason, response_text, tool_result correlation |
| 2026-06-06 | Copilot CLI validado — mesmo interceptor funciona via HTTPS_PROXY. Modelo gpt-5.4 |
| 2026-06-06 | VS Code OTLP: captureContent=true habilitado, port-forward 4318 ativo |
