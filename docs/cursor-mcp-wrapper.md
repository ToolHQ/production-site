# Agent Meter MCP Wrapper — Cursor Setup

## Prerequisites

- Agent Meter MCP wrapper binary (`agent-meter-mcp-wrapper`) in PATH or a known location
- An MCP server you want to monitor (e.g. filesystem, GitHub, custom)

## Configuration

Cursor uses `.cursor/mcp.json` in your project root for MCP server configuration.

### Option 1: Wrap an existing stdio MCP server

If your MCP server runs via stdio (e.g. `npx @modelcontextprotocol/server-filesystem`), you need to run it as HTTP first, then proxy through the wrapper.

### Option 2: HTTP MCP server (recommended)

If your MCP server exposes an HTTP endpoint, point Cursor to the wrapper:

```jsonc
// .cursor/mcp.json
{
  "mcpServers": {
    "my-server-metered": {
      "url": "http://localhost:3001",
      "transportType": "sse"
    }
  }
}
```

Then run the wrapper:

```bash
export MCP_UPSTREAM_URL=http://localhost:5000  # your real MCP server
export AGENT_METER_COLLECTOR_URL=https://agent-meter.dnor.io/api/events
export AGENT_METER_IDE=cursor
export AGENT_METER_AGENT=cursor-agent
export AGENT_METER_REPO=$(basename $(git rev-parse --show-toplevel))
export AGENT_METER_BRANCH=$(git branch --show-current)
export MCP_SERVER_NAME=my-server

agent-meter-mcp-wrapper
```

### Option 3: Shell wrapper script

Create `~/bin/mcp-wrapper-cursor.sh`:

```bash
#!/bin/bash
export MCP_UPSTREAM_URL="${1:-http://localhost:5000}"
export AGENT_METER_COLLECTOR_URL="https://agent-meter.dnor.io/api/events"
export AGENT_METER_IDE="cursor"
export AGENT_METER_AGENT="cursor-agent"
export AGENT_METER_REPO="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || echo unknown)")"
export AGENT_METER_BRANCH="$(git branch --show-current 2>/dev/null || echo main)"
export MCP_SERVER_NAME="${2:-upstream}"

exec agent-meter-mcp-wrapper
```

## Environment Variables

Set these in your shell profile (`~/.bashrc`, `~/.zshrc`) for persistent metering:

```bash
export AGENT_METER_IDE=cursor
export AGENT_METER_COLLECTOR_URL=https://agent-meter.dnor.io/api/events
```

## Verifying

1. Start the wrapper and make a tool call in Cursor
2. Check the Agent Meter dashboard at `https://agent-meter.dnor.io`
3. You should see events with `ide=cursor` appearing in the timeline
