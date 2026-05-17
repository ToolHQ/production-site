# T-227 — agent-meter: Copilot/VSCode integration

**Owner**: Copilot/VSCode
**Priority**: 🔼 High
**Estimate**: 1h
**Status**: ✅ Done

## Goal

Integrate Copilot/VSCode agent sessions with agent-meter: install CLI, send tool-call events, configure OTEL.

## Tasks

- [x] `apps/agent-meter/scripts/setup-agent.sh` criado — script universal que compila CLI + MCP wrapper, configura env vars
- [x] `.agents/skills/agent-meter-integration/SKILL.md` criado — skill reutilizável por qualquer agente
- [x] Env vars: `setup-agent.sh --agent copilot` define `AGENT_METER_IDE=copilot-vscode`
- [x] `--mcp-wrapper` flag compila `agent-meter-mcp-wrapper` e configura `MCP_UPSTREAM_URL` + `MCP_WRAPPER_LISTEN`
- [x] CLI, wrapper e OTEL documentados na skill

## Como usar

```bash
cd ~/production-site-opencode   # qualquer worktree
apps/agent-meter/scripts/setup-agent.sh --agent copilot --mcp-wrapper
```

## Dependencies

- T-225 (OTEL docs) — Done
