# Agent Meter MCP Wrapper — OpenCode Setup

## Prerequisites

- Agent Meter MCP wrapper binary (`agent-meter-mcp-wrapper`) in PATH
- OpenCode configured with MCP servers

## Configuration

OpenCode uses `~/.opencode/config.json` (or project-level `.opencode/config.json`) for MCP:

```jsonc
// ~/.opencode/config.json
{
  "mcpServers": {
    "my-server": {
      "type": "http",
      "url": "http://localhost:3001"
    }
  }
}
```

## Running the Wrapper

```bash
export MCP_UPSTREAM_URL=http://localhost:5000  # your real MCP server
export AGENT_METER_COLLECTOR_URL=https://agent-meter.dnor.io/api/events
export AGENT_METER_IDE=opencode
export AGENT_METER_AGENT=opencode
export AGENT_METER_REPO=$(basename $(git rev-parse --show-toplevel))
export AGENT_METER_BRANCH=$(git branch --show-current)
export MCP_SERVER_NAME=my-server

agent-meter-mcp-wrapper
```

## Shell Alias

Add to `~/.bashrc` or `~/.zshrc`:

```bash
alias mcp-meter='AGENT_METER_IDE=opencode AGENT_METER_COLLECTOR_URL=https://agent-meter.dnor.io/api/events agent-meter-mcp-wrapper'
```

Usage:

```bash
MCP_UPSTREAM_URL=http://localhost:5000 MCP_SERVER_NAME=github mcp-meter
```

## Per-Task Metering

OpenCode supports task-based workflows. Pass the task ID for cost attribution:

```bash
export AGENT_METER_TASK_ID=T-339
export AGENT_METER_SKILL=docs-generation
```

## Verifying

Check events at `https://agent-meter.dnor.io` — filter by `ide=opencode`.
