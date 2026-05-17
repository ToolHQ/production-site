# T-228 — agent-meter: Cursor integration

**Owner**: Cursor / AI Radar
**Priority**: 🔼 High
**Estimate**: 1h
**Status**: Backlog

## Goal

Integrate Cursor agent sessions with agent-meter: install CLI, send tool-call events, configure OTEL.

## Tasks

- [ ] Adicionar `agent-meter` CLI ao PATH na worktree `~/production-site-cursor`
- [ ] Configurar env vars: `AGENT_METER_COLLECTOR_URL=http://agent-meter:3000`, `AGENT_METER_IDE=cursor`
- [ ] Configurar MCP wrapper proxy para medir chamadas de ferramentas Cursor
- [ ] Opcional: configurar OTEL exporter (`OTEL_EXPORTER_OTLP_ENDPOINT`)
- [ ] Documentar no AGENTS.md ou CURSOR-QUEUE.md

## Dependencies

- T-225 (OTEL docs) para referência de env vars
