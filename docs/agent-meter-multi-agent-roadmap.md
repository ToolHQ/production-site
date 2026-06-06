# Agent-Meter — Roadmap Multi-Agent Support

**Data:** 2026-06-04  
**Autor:** Copilot/VSCode  
**Status:** Planning

---

## 1. Análise: o que cada ferramenta emite hoje

### 1.1 Mapa de integração por ferramenta

| Ferramenta                            | Tipo de telemetria                 | Caminho de ingestão         | Status hoje                       |
| ------------------------------------- | ---------------------------------- | --------------------------- | --------------------------------- |
| **VS Code Copilot**                   | JSON OTLP (GenAI semconv)          | OTLP endpoint `/v1/traces`  | ✅ Suportado                      |
| **Antigravity**                       | Protobuf OTLP                      | OTLP endpoint `/v1/traces`  | ✅ Suportado                      |
| **Claude Code** (Anthropic CLI)       | JSON OTLP (GenAI semconv)          | OTLP endpoint `/v1/traces`  | 🟡 Detectado parcialmente         |
| **Codex CLI** (OpenAI)                | JSON OTLP (GenAI semconv, OAI SDK) | OTLP endpoint `/v1/traces`  | 🟡 Detecção errada no `infer_ide` |
| **Cursor** (IDE)                      | Telemetria própria (fechada)       | **MCP wrapper**             | 🔴 MCP wrapper apenas             |
| **OpenCode**                          | Telemetria própria (TS interno)    | **MCP wrapper**             | 🟡 Detectado, sem OTLP            |
| **Copilot CLI** (github/copilot-cli)  | Métricas internas → GitHub         | **MCP wrapper**             | 🔴 MCP wrapper apenas             |
| **Cursor CLI**                        | Não existe como produto separado   | —                           | ➖ N/A                            |
| **Copilot for Eclipse**               | JSON OTLP (semelhante ao VSCode)   | OTLP endpoint + detecção UA | 🟡 Sem detecção de UA             |
| **MCP OTEL semconv** (`tools/call X`) | JSON OTLP (span name `tools/call`) | Parser novo necessário      | 🔴 Não suportado                  |

### 1.2 Três caminhos de ingestão

```
┌─────────────────────────────────────────────────────────────────────┐
│                         agent-meter-collector                        │
│                                                                     │
│  ┌──────────────────┐   ┌──────────────────┐   ┌────────────────┐  │
│  │  OTLP JSON       │   │  OTLP Protobuf   │   │  REST API      │  │
│  │  /v1/traces      │   │  /v1/traces      │   │  /events/*     │  │
│  │  (JSON CT)       │   │  (proto CT)      │   │                │  │
│  └────────┬─────────┘   └────────┬─────────┘   └───────┬────────┘  │
└───────────┼──────────────────────┼──────────────────────┼───────────┘
            │                      │                      │
┌───────────▼──────────────────────▼──────────────────────▼───────────┐
│  VS Code Copilot   │   Antigravity   │   Scripts/CLI sem SDK        │
│  Claude Code       │                │   Eclipse (futuro)           │
│  Codex CLI         │                │                              │
│  Copilot Eclipse   │                │                              │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                      agent-meter-mcp-wrapper                        │
│  (proxy JSON-RPC: intercepta tools/call → posta no collector)      │
└────────────────────────────┬────────────────────────────────────────┘
                             │
              ┌──────────────▼──────────────┐
              │  Cursor (IDE)               │
              │  OpenCode                   │
              │  Copilot CLI                │
              │  Qualquer cliente MCP       │
              └─────────────────────────────┘
```

---

## 2. Research por ferramenta

### Claude Code (Anthropic CLI)

- **OTLP nativo**: SIM. Env vars: `CLAUDE_CODE_OTEL_ENDPOINT`, `CLAUDE_CODE_OTEL_HEADERS`.
- **Formato**: JSON OTLP, segue GenAI semconv. Span names: `execute_tool <tool>`, `chat <model>`.
- **Atributos específicos**: `gen_ai.system = "anthropic"`, `gen_ai.request.model = "claude-*"`.
- **service.name**: `claude` ou `claude-code`.
- **Compatibilidade**: O parser JSON existente já deve funcionar — os span names são idênticos ao VS Code.
- **Gap atual**: `infer_ide` não detecta `claude-code` no user-agent. Sem fixture de teste.
- **Configuração do usuário**: `CLAUDE_CODE_OTEL_ENDPOINT=http://agent-meter.dnor.io/v1/traces claude <cmd>`

### Codex CLI (OpenAI)

- **OTLP nativo**: SIM (via OpenAI SDK com OTel instrumentation).
- **Formato**: JSON OTLP. Span names: `chat <model>`, `execute_tool <tool>`.
- **Atributos**: `gen_ai.system = "openai"`, `gen_ai.request.model = "gpt-*" | "o*"`.
- **service.name**: `codex`, `openai-codex`, ou `openai`.
- **Bug atual**: `infer_ide` mapeia `rust-rover` → `codex` — ERRADO. Rust Rover é o IDE da JetBrains.
- **Fix**: Detectar via `ua.contains("codex")` ou `svc.contains("codex")`.

### Cursor (IDE)

- **OTLP**: NÃO. Cursor envia telemetria apenas para seus servidores internos.
- **Workaround**: MCP wrapper intercepta todos os `tools/call`. Cursor suporta MCP servers custom.
- **Configuração**: `cursor://settings` → MCP Servers → apontar todos os servidores MCP para `agent-meter-mcp-wrapper:3001`.
- **Limitação**: Não captura LLM calls (tokens, modelos) — apenas tool calls via MCP.

### OpenCode (SST)

- **OTLP**: NÃO confirmado. Sistema de eventos interno em TypeScript.
- **Workaround**: MCP wrapper. OpenCode tem configuração `~/.opencode/config.json` com MCP servers.
- **Parcialmente suportado**: `infer_ide` detecta via service name `opencode`, mas sem dados reais validados.

### GitHub Copilot CLI (novo — `github/copilot-cli`)

- **Nota**: O antigo `gh copilot` foi arquivado em out/2025. O novo é o `github/copilot-cli`.
- **OTLP**: NÃO. Envia métricas agregadas para GitHub Analytics internamente.
- **Workaround**: Se o Copilot CLI usa MCP servers → MCP wrapper. Mas é um agente autônomo, não IDE.
- **Limitação**: Difícil capturar sem OTLP ou MCP proxy.

### Copilot for Eclipse

- **OTLP**: Possivelmente SIM — plugin Eclipse da Microsoft usa o mesmo SDK que VS Code.
- **User-Agent esperado**: Pode conter `Eclipse` ou `JDT` ou `eclipse-copilot`.
- **Configuração**: Mesmo endpoint OTLP, mas detecção de IDE precisa do user-agent correto.

### MCP OTel Semconv (`tools/call <tool>`)

- **Novo padrão**: Conforme `opentelemetry.io/docs/specs/semconv/gen-ai/mcp/`, os spans MCP usam:
  - Span name: `tools/call <tool_name>` (CLIENT ou SERVER)
  - `mcp.method.name = "tools/call"`, `gen_ai.tool.name = "<tool>"`, `mcp.session.id`
  - `gen_ai.tool.call.arguments` (opt-in), `gen_ai.tool.call.result` (opt-in — nome diferente do que temos!)
- **Gap atual**: Parser só conhece `execute_tool`, `chat`, `invoke_agent`. Não trata `tools/call <tool>`.
- **Impacto**: Ferramentas que seguirem o novo semconv (ex.: Claude Code SDK, OpenAI SDK recente) emitirão este formato.

---

## 3. Gaps de Implementação

### 3.1 Parser OTLP (`otlp/mod.rs`)

| Gap                                                            | Severidade | Descrição                                                         |
| -------------------------------------------------------------- | ---------- | ----------------------------------------------------------------- |
| `tools/call <tool>` não parseado                               | 🔴 Alta    | Novo semconv MCP — ignorado hoje com `warn!(unknown span)`        |
| `claude-code` não detectado em `infer_ide`                     | 🟡 Média   | Dados entram como `ide = NULL`                                    |
| `codex` mapeado errado (`rust-rover`)                          | 🟡 Média   | `ide` errado para Codex CLI                                       |
| `eclipse` / `copilot-eclipse` não detectado                    | 🟡 Média   | Sem suporte para Eclipse plugin                                   |
| `gen_ai.tool.call.result` (MCP semconv) ≠ `gen_ai.tool.output` | 🟡 Média   | Resultado pode não ser capturado se a ferramenta usar o novo nome |
| `mcp.session.id` não extraído como `conversation_id`           | 🟡 Média   | Conversas MCP não agrupadas corretamente                          |
| `copilot-cli` / `copilot_cli` não detectado                    | 🟢 Baixa   | Só via mcp-wrapper mesmo                                          |

### 3.2 Testes

| Gap                                                | Severidade | Descrição                               |
| -------------------------------------------------- | ---------- | --------------------------------------- |
| Zero fixtures de OTLP reais por ferramenta         | 🔴 Alta    | Regressão não detectável                |
| Sem teste para span `chat <model>`                 | 🟡 Média   | Parser existe mas sem cobertura         |
| Sem teste para span `tools/call <tool>`            | 🔴 Alta    | Parser não existe                       |
| Sem teste de `infer_ide`                           | 🟡 Média   | Pode regredir silenciosamente           |
| Sem validação de `tool_arguments` parsed como JSON | 🟡 Média   | Pode vir como string e não ser parseado |

### 3.3 Dashboard/UI

| Gap                                        | Severidade | Descrição                                           |
| ------------------------------------------ | ---------- | --------------------------------------------------- |
| Sem breakdown "By IDE"                     | 🟡 Média   | Não dá pra saber qual agent está gerando mais custo |
| Sem indicador de "source" (OTLP, MCP, API) | 🟢 Baixa   | Nice-to-have para debug                             |

### 3.4 Documentação

| Gap                                          | Descrição                               |
| -------------------------------------------- | --------------------------------------- |
| Sem guia de configuração por ferramenta      | Como apontar cada tool para o collector |
| Sem guia do MCP wrapper para Cursor/OpenCode | Como interceptar MCP calls              |

---

## 4. Roadmap de Tasks (T-333 a T-342)

### Sprint 1 — Parser + Detecção (impacto imediato, sem UI)

#### T-333 — Claude Code: OTLP ingestion + detecção + fixture

**Prioridade**: 🔼 High | **Owner**: Copilot/VSCode | **Esforço**: ~3h

Aceitar telemetria do Claude Code corretamente.

**Subtasks**:

1. Adicionar `claude` / `claude-code` em `infer_ide` (user-agent + service.name)
2. Adicionar `gen_ai.tool.call.result` como fallback em `tool_result` (MCP semconv novo nome)
3. Criar `tests/fixtures/claude_code_execute_tool.json` — payload OTLP real
4. Criar `tests/fixtures/claude_code_chat.json`
5. Adicionar `test_otlp_claude_code_tool_call()` + `test_otlp_claude_code_chat()` em `api.rs`
6. Escrever `docs/setup/claude-code.md` (como configurar `CLAUDE_CODE_OTEL_ENDPOINT`)

**Definition of Done**: Fixture processada sem warnings, `ide = "claude-code"`, tokens e modelo corretos.

---

#### T-334 — Codex CLI: corrigir detecção + fixture

**Prioridade**: 🔼 High | **Owner**: Copilot/VSCode | **Esforço**: ~2h

Corrigir bug onde `rust-rover` → `codex` (errado). Rust Rover é IDE JetBrains.

**Subtasks**:

1. Corrigir `infer_ide`: remover `rust-rover` da lógica de codex
2. Adicionar detecção: `ua.contains("codex") || svc.contains("codex") || svc.contains("openai-codex")`
3. Adicionar detecção de `rust-rover` → `ide = "rust-rover"` (separado)
4. Criar fixture `tests/fixtures/codex_cli_execute_tool.json`
5. Adicionar teste `test_otlp_codex_cli()`
6. Escrever `docs/setup/codex-cli.md`

**Definition of Done**: `rust-rover` não mais mapeado como `codex`. Fixture de Codex processa com `ide = "codex"`.

---

#### T-335 — MCP OTel semconv: parser para `tools/call <tool>`

**Prioridade**: 🔴 Critical | **Owner**: Copilot/VSCode | **Esforço**: ~4h

Suporte ao novo formato de span MCP (`tools/call get-weather` em vez de `execute_tool get-weather`).

**Subtasks**:

1. Adicionar branch `span_name.starts_with("tools/call")` no parser JSON
2. Adicionar branch `span_name.starts_with("tools/call")` no parser Protobuf
3. Extrair `gen_ai.tool.name` do atributo (vem como `get-weather` sem o prefixo)
4. Mapear `mcp.session.id` como fallback para `conversation_id`
5. Mapear `mcp.method.name` → campo no metadata
6. Tratar `gen_ai.tool.call.result` como alias para `tool_result`
7. Criar fixture `tests/fixtures/mcp_semconv_tools_call.json`
8. Adicionar teste `test_otlp_mcp_semconv_tools_call()`

**Definition of Done**: Span `tools/call get-weather` processado sem warning. Tool name extraído corretamente.

---

#### T-336 — Copilot for Eclipse: detecção UA

**Prioridade**: 🟢 Low | **Owner**: Copilot/VSCode | **Esforço**: ~1h

**Subtasks**:

1. Pesquisar user-agent real emitido pelo Eclipse Copilot plugin (pode ser `eclipse`, `jdt`, `che`)
2. Adicionar detecção em `infer_ide`
3. Criar fixture se conseguir capturar payload real
4. Escrever `docs/setup/copilot-eclipse.md`

---

### Sprint 2 — Testes e Harness

#### T-337 — Test harness: fixtures OTLP por ferramenta

**Prioridade**: 🔼 High | **Owner**: Copilot/VSCode | **Esforço**: ~5h

Criar suíte de testes de regressão com fixtures reais.

**Estrutura de arquivos**:

```
apps/agent-meter/crates/collector/tests/
  fixtures/
    vscode_copilot_execute_tool.json       # já existe em produção
    vscode_copilot_chat.json
    antigravity_execute_tool.proto.bin     # binário proto
    claude_code_execute_tool.json
    claude_code_chat.json
    codex_cli_execute_tool.json
    mcp_semconv_tools_call.json
    cursor_mcp_wrapper_event.json          # via mcp-wrapper
    opencode_mcp_wrapper_event.json
  otlp_regression.rs                      # novo arquivo de testes
```

**Subtasks**:

1. Criar arquivo `tests/otlp_regression.rs`
2. Helper `fn post_otlp_fixture(base_url, path) -> serde_json::Value`
3. Teste por fixture: verificar `ide`, `tool_name`, `model`, `tokens`, `conversation_id`
4. Testes negativos: payload inválido, span desconhecido, atributos ausentes
5. Integrar ao `cargo test` existente

**Definition of Done**: `cargo test` verde com cobertura de todos os parsers.

---

#### T-338 — infer_ide: refactor + unit tests isolados

**Prioridade**: 🟡 Medium | **Owner**: Copilot/VSCode | **Esforço**: ~2h

**Subtasks**:

1. Extrair `infer_ide` para módulo próprio `otlp/ide.rs`
2. Criar tabela de regras: `(ua_pattern, svc_pattern) → ide`
3. Adicionar `#[cfg(test)] mod tests` com ~15 casos unitários
4. Casos: vscode, cursor, antigravity, opencode, codex, claude-code, rust-rover, eclipse, copilot-cli, unknown

---

### Sprint 3 — MCP Wrapper + Setup

#### T-339 — MCP wrapper: guia de configuração multi-agent

**Prioridade**: 🟡 Medium | **Owner**: Copilot/VSCode | **Esforço**: ~3h

Documentação + templates de configuração para cada ferramenta usar o MCP wrapper.

**Subtasks**:

1. `docs/setup/cursor-mcp-wrapper.md` — como configurar `.cursor/mcp.json`
2. `docs/setup/opencode-mcp-wrapper.md` — como configurar `~/.opencode/config.json`
3. `docs/setup/copilot-cli-mcp-wrapper.md` — se o Copilot CLI expõe MCP server config
4. Template genérico: `docs/setup/mcp-wrapper-generic.md`
5. Adicionar seção no README do mcp-wrapper

**Config padrão para Cursor** (`.cursor/mcp.json`):

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "agent-meter-mcp-wrapper",
      "args": [
        "--upstream",
        "npx @modelcontextprotocol/server-filesystem /workspace",
        "--collector",
        "http://agent-meter.dnor.io/events/tool-call"
      ]
    }
  }
}
```

---

#### T-340 — MCP wrapper: passar `ide` como header/env

**Prioridade**: 🟡 Medium | **Owner**: Copilot/VSCode | **Esforço**: ~2h

Hoje o mcp-wrapper não sabe qual IDE está usando ele. Adicionar mecanismo para identificar a fonte.

**Subtasks**:

1. Aceitar env var `AGENT_METER_IDE` no mcp-wrapper
2. Aceitar header `X-Agent-IDE` nas requisições (se o cliente puder setá-lo)
3. Incluir `ide` no evento postado ao collector
4. Atualizar `docs/setup/*.md` com instruções de configuração do env

---

### Sprint 4 — Dashboard

#### T-341 — Dashboard: breakdown "By IDE"

**Prioridade**: 🟡 Medium | **Owner**: Copilot/VSCode | **Esforço**: ~3h

Mostrar distribuição de uso por IDE/agent no dashboard.

**Subtasks**:

1. Adicionar endpoint `GET /api/reports/by-ide` → `{ide: string, calls: int, tokens: int, cost: float}[]`
2. SQL: `SELECT ide, COUNT(*), SUM(estimated_input_tokens+estimated_output_tokens), SUM(estimated_cost_usd) FROM agent_tool_calls GROUP BY ide`
3. Adicionar seção "By Agent / IDE" no `dashboard.html` com barra horizontal
4. Adicionar filtro de período (7d/30d/all)

---

### Sprint 5 — Validação ao Vivo

#### T-342 — Live validation harness por ferramenta

**Prioridade**: 🟡 Medium | **Owner**: Copilot/VSCode | **Esforço**: ~4h

Scripts de validação end-to-end: simular envio de payload e verificar que aparece corretamente na UI.

**Subtasks**:

1. `scripts/harness/validate_claude_code.sh` — POST fixture + curl API + verifica
2. `scripts/harness/validate_codex_cli.sh`
3. `scripts/harness/validate_mcp_semconv.sh`
4. `scripts/harness/validate_all_agents.sh` — roda todos em sequência
5. Cada script retorna exit 0 se ok, 1 se falhar, com output descritivo
6. Integrar ao CI (GitHub Actions: executa na PR do agent-meter)

---

## 5. Ordem de execução recomendada

```
T-333 (Claude Code)    ← Deploy imediato, usuário já tem Claude Code
T-334 (Codex fix)      ← Bugfix simples
T-335 (MCP semconv)    ← Crítico para futuro
T-337 (Fixtures)       ← Regressão
T-338 (infer_ide)      ← Cleanup
T-340 (MCP IDE ident.) ← Melhoria MCP wrapper
T-339 (Guias setup)    ← Documentação
T-341 (Dashboard IDE)  ← UI
T-336 (Eclipse)        ← Baixa prioridade
T-342 (Harness)        ← CI/CD
```

---

## 6. Matriz de Cobertura Final (após roadmap)

| Ferramenta           | OTLP  | MCP wrapper | API | IDE detectado | Fixtures | Guia  |
| -------------------- | ----- | ----------- | --- | ------------- | -------- | ----- |
| VS Code Copilot      | ✅    | —           | —   | ✅            | T-337    | —     |
| Antigravity          | ✅    | —           | —   | ✅            | T-337    | —     |
| **Claude Code**      | T-333 | —           | —   | T-333         | T-333    | T-333 |
| **Codex CLI**        | T-334 | —           | —   | T-334         | T-337    | T-334 |
| **Cursor**           | —     | T-339       | —   | T-340         | T-337    | T-339 |
| **OpenCode**         | —     | T-339       | —   | T-340         | T-337    | T-339 |
| **Copilot CLI**      | —     | T-339       | —   | T-340         | T-342    | T-339 |
| **Copilot Eclipse**  | T-336 | —           | —   | T-336         | T-336    | T-336 |
| **MCP OTel semconv** | T-335 | —           | —   | —             | T-335    | T-339 |

---

## 7. Notas técnicas

### Claude Code — como configurar

```bash
export CLAUDE_CODE_OTEL_ENDPOINT=https://agent-meter.dnor.io/v1/traces
export CLAUDE_CODE_OTEL_HEADERS="Authorization=Bearer <token>"
claude <command>
```

### Codex CLI — como configurar (OpenAI SDK)

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=https://agent-meter.dnor.io
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer <token>"
export OTEL_SERVICE_NAME=codex
codex <command>
```

### `gen_ai.tool.call.result` vs `gen_ai.tool.output`

- **Antigo** (o que temos): `gen_ai.tool.output` — usado por VS Code SDK hoje
- **Novo** (MCP semconv): `gen_ai.tool.call.result` — novo padrão oficial
- Precisamos suportar ambos (já temos multi-fallback para input, replicar para output)
