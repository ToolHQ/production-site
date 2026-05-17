# T-226 — agent-meter: Antigravity integration

**Owner**: Antigravity
**Priority**: 🔼 High
**Estimate**: 1h
**Status**: Backlog

## Goal

Integrate Antigravity agent sessions with agent-meter: install CLI, send tool-call events, configure OTEL.

## Tasks

- [ ] Adicionar `agent-meter` CLI ao PATH na worktree `~/production-site-antigravity`
- [ ] Configurar env vars: `AGENT_METER_COLLECTOR_URL=http://agent-meter:3000`, `AGENT_METER_IDE=antigravity`
- [ ] Documentar no AGENTS.md ou numa skill de integração
- [ ] Criar hook/wrapper que envia eventos de tool-call ao collector
- [ ] Opcional: configurar OTEL exporter (`OTEL_EXPORTER_OTLP_ENDPOINT`)

## Dependencies

- T-225 (OTEL docs) para referência de env vars
