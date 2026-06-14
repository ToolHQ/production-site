# Agent Meter MCP Wrapper — Copilot CLI Setup

## Overview

GitHub Copilot CLI (`gh copilot`) doesn't natively use MCP, but tool calls from Copilot extensions and VS Code Copilot Chat can be routed through the wrapper when using HTTP-based MCP servers.

## VS Code Copilot + MCP

VS Code's Copilot Chat supports MCP servers via `.vscode/mcp.json`. To meter them:

### 1. Start the wrapper

```bash
export MCP_UPSTREAM_URL=http://localhost:5000  # real MCP server
export AGENT_METER_COLLECTOR_URL=https://agent-meter.dnor.io/api/events
export AGENT_METER_IDE=vscode
export AGENT_METER_AGENT=copilot
export AGENT_METER_REPO=$(basename $(git rev-parse --show-toplevel))
export AGENT_METER_BRANCH=$(git branch --show-current)
export MCP_SERVER_NAME=my-server

agent-meter-mcp-wrapper
```

### 2. Configure VS Code MCP

```jsonc
// .vscode/mcp.json
{
  "servers": {
    "my-server-metered": {
      "type": "http",
      "url": "http://localhost:3001"
    }
  }
}
```

## X-Agent-IDE Header

If you can't set env vars (e.g. running in a container), send the `X-Agent-IDE` header with each request:

```bash
curl -X POST http://localhost:3001 \
  -H "Content-Type: application/json" \
  -H "X-Agent-IDE: copilot" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"read_file","arguments":{"path":"README.md"}}}'
```

## Copilot CLI Interceptor (HTTPS Proxy)

For intercepting Copilot CLI LLM calls (not MCP), use `agent-meter-proxy` instead:

```bash
# See docs/agent-meter-telemetry-coverage.md for the HTTPS proxy setup
HTTPS_PROXY=http://localhost:8080 gh copilot suggest "explain this code"
```

## Verifying

Events appear at `https://agent-meter.dnor.io` with `ide=vscode` and `agent=copilot`.
