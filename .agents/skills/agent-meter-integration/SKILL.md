# agent-meter Integration

> Telemetria e FinOps para agentes de IA — envie eventos de tool-call, gerencie tasks e consulte reports.

## Setup rápido

```bash
# OpenCode (worktree ~/production-site-opencode)
apps/agent-meter/scripts/setup-agent.sh --agent opencode

# Cursor (worktree ~/production-site-cursor)
apps/agent-meter/scripts/setup-agent.sh --agent cursor --mcp-wrapper

# Copilot/VSCode (worktree ~/production-site-copilot)
apps/agent-meter/scripts/setup-agent.sh --agent copilot --mcp-wrapper

# Antigravity (worktree ~/production-site-antigravity)
apps/agent-meter/scripts/setup-agent.sh --agent antigravity

# Codex (worktree ~/production-site-rust-rover-claude)
apps/agent-meter/scripts/setup-agent.sh --agent codex
```

O script:
1. Compila `agent-meter` CLI (cargo ou docker)
2. Cria `~/.config/agent-meter/env.sh` com env vars corretas
3. Adiciona source ao `~/.bashrc`
4. Opcional: compila `agent-meter-mcp-wrapper` e configura vars

## Env vars

| Var | Default | Descrição |
|-----|---------|-----------|
| `AGENT_METER_COLLECTOR_URL` | `http://agent-meter:3000` | URL do collector (in-cluster) |
| `AGENT_METER_TASK_ID` | — | Task ID ativa (set automático via `task start`) |
| `AGENT_METER_IDE` | — | IDE do agente: `opencode`, `cursor`, `copilot-vscode`, `antigravity`, `rust-rover` |
| `AGENT_METER_AGENT` | — | Nome do agente |
| `AGENT_METER_REPO` | — | Repositório atual |
| `AGENT_METER_BRANCH` | — | Branch atual |
| `AGENT_METER_SKILL` | — | Skill em uso |

## Uso diário

### Task lifecycle

```bash
# Iniciar task
agent-meter task start T-999 --skill code-review --repo production-site

# Listar tasks ativas
agent-meter task list

# Finalizar task
agent-meter task end T-999
```

### Tool-call events

```bash
agent-meter event tool-call \
  --tool-name search_code \
  --mcp-server github \
  --ok \
  --request-bytes 250 \
  --response-bytes 12000
```

### Reports

```bash
agent-meter report top-tools --limit 10
agent-meter report top-tasks
agent-meter report top-mcp-servers
```

## MCP wrapper

> Para agentes que usam MCP via HTTP (Cursor, Copilot).

O `agent-meter-mcp-wrapper` é um proxy HTTP que:

- Intercepta `tools/list` e `tools/call`
- Mede: bytes request/response, duração, success/error, SHA256
- Envia métricas ao collector via `POST /events/tool-call`
- Passa-through de outros métodos MCP

### Configuração

```bash
# Iniciar wrapper (porta :3001, upstream :3002)
export MCP_UPSTREAM_URL=http://localhost:3002
export MCP_WRAPPER_LISTEN=:3001
agent-meter-mcp-wrapper &
```

No Cursor, configurar MCP server com URL apontando para o wrapper:
```
URL: http://localhost:3001
```

## OTEL (opcional)

O collector exporta spans via OTLP se `OTEL_EXPORTER_OTLP_ENDPOINT` estiver setado.

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_SERVICE_NAME=agent-meter
```

Ver `docs/agent-meter-otel.md` para detalhes.

## Materiais

- `apps/agent-meter/scripts/setup-agent.sh` — setup automatizado
- `apps/agent-meter/crates/cli/` — código do CLI
- `apps/agent-meter/crates/collector/` — collector HTTP
- `apps/agent-meter/crates/mcp-wrapper/` — proxy MCP
- `apps/agent-meter/docs/agent-meter-otel.md` — guia OTEL
- `apps/agent-meter/scripts/smoke-otel.sh` — smoke test
