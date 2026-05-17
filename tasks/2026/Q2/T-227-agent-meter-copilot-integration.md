# T-227 — agent-meter: Copilot/VSCode integration

**Owner**: Copilot/VSCode
**Priority**: 🔼 High
**Estimate**: 1h
**Status**: Backlog

## Goal

Integrate Copilot/VSCode agent sessions with agent-meter: install CLI, send tool-call events, configure OTEL.

## Tasks

- [ ] Adicionar `agent-meter` CLI ao PATH na worktree `~/production-site-copilot`
- [ ] Configurar env vars: `AGENT_METER_COLLECTOR_URL=http://agent-meter:3000`, `AGENT_METER_IDE=copilot-vscode`
- [ ] Configurar MCP wrapper proxy para medir chamadas de ferramentas VSCode
- [ ] Opcional: configurar OTEL exporter (`OTEL_EXPORTER_OTLP_ENDPOINT`)
- [ ] Documentar no AGENTS.md

## Dependencies

- T-225 (OTEL docs) para referência de env vars
