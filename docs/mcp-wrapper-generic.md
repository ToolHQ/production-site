# Agent Meter MCP Wrapper — Generic Setup Guide

## Overview

The **agent-meter-mcp-wrapper** is a transparent HTTP proxy that sits between your MCP client (IDE/agent) and any MCP server. It intercepts JSON-RPC tool calls, measures timing/size, and reports events to the Agent Meter collector for cost attribution and observability.

```
┌─────────┐     JSON-RPC      ┌───────────────┐     JSON-RPC      ┌────────────┐
│  IDE /  │ ──────────────────▸│  MCP Wrapper  │ ──────────────────▸│ MCP Server │
│  Agent  │ ◂──────────────────│  (port 3001)  │ ◂──────────────────│ (upstream) │
└─────────┘                    └───────┬───────┘                    └────────────┘
                                       │ POST /api/events
                                       ▼
                               ┌───────────────┐
                               │   Collector   │
                               │  (port 8081)  │
                               └───────────────┘
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MCP_WRAPPER_LISTEN` | No | `0.0.0.0:3001` | Address:port the wrapper listens on |
| `MCP_UPSTREAM_URL` | **Yes** | `http://localhost:3001` | URL of the actual MCP server to proxy to |
| `AGENT_METER_COLLECTOR_URL` | No | `http://localhost:8081` | Agent Meter collector endpoint |
| `AGENT_METER_IDE` | No | — | IDE identifier (e.g. `cursor`, `vscode`, `opencode`) |
| `AGENT_METER_AGENT` | No | — | Agent name (e.g. `copilot`, `claude-code`, `aider`) |
| `AGENT_METER_REPO` | No | — | Repository name for attribution |
| `AGENT_METER_BRANCH` | No | — | Current git branch |
| `AGENT_METER_TASK_ID` | No | — | Task/ticket ID for cost tracking |
| `AGENT_METER_SKILL` | No | — | Skill/workflow name |
| `MCP_SERVER_NAME` | No | `upstream` | Name label for the upstream MCP server |

## Headers

The wrapper also accepts the following HTTP headers (useful when env vars aren't practical):

| Header | Description |
|--------|-------------|
| `X-Agent-IDE` | IDE identifier (fallback if `AGENT_METER_IDE` env is not set) |

## Running Locally

```bash
# Start the wrapper proxying to an MCP server on port 5000
export MCP_UPSTREAM_URL=http://localhost:5000
export AGENT_METER_COLLECTOR_URL=https://agent-meter.dnor.io/api/events
export AGENT_METER_IDE=cursor
export AGENT_METER_REPO=my-project

agent-meter-mcp-wrapper
# Listening on 0.0.0.0:3001
```

Then configure your IDE to connect to `http://localhost:3001` instead of the MCP server directly.

## Running in Kubernetes

The wrapper is deployed as a sidecar or standalone deployment. See `apps/agent-meter/k8s/mcp-wrapper.yaml`.

## What Gets Captured

For each tool call:
- `event_id` (UUID v4)
- `tool_name` (from JSON-RPC `method` or `params.name`)
- `started_at` / `ended_at` (RFC3339)
- `ok` (boolean)
- `request_bytes` / `response_bytes`
- `request_sha256` / `response_sha256`
- `tool_arguments` (first 4KB of request params)
- `tool_result` (first 4KB of response)
- `tool_call_id` (JSON-RPC `id`)
- All env metadata: `ide`, `agent`, `repo`, `branch`, `task_id`, `skill`, `mcp_server`
