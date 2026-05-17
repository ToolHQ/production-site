# T-225 — agent-meter: OTEL integration + multi-agent docs

**Owner**: OpenCode
**Priority**: 🔼 High
**Estimate**: 2h
**Status**: Em andamento

## Goal

Document and implement how all agents (OpenCode, Cursor, Copilot/VSCode, Antigravity, Codex) send OTEL traces to the agent-meter collector, and create a central reference doc.

## Tasks

- [x] Implementar suporte OTEL no collector (Fase 3) — `tracing_opentelemetry::layer()`, upgrade 0.25→0.26, zero-crash sem endpoint
- [ ] Criar `docs/agent-meter-otel.md` com:
  - Como configurar `OTEL_EXPORTER_OTLP_ENDPOINT` apontando pro collector
  - `OTEL_SERVICE_NAME` recomendado por agente (opencode, cursor, copilot-vscode, antigravity, codex)
  - Mapeamento de spans: `agent.tool_call` → atributos do spec
  - Exemplo de deploy: variáveis de ambiente no container/ConfigMap
- [ ] Criar script de smoke OTEL para validar pipeline: `scripts/smoke-otel.sh`
- [ ] Deploy da configuração no cluster (ConfigMap, env vars nos deployments)

## Dependencies

- agent-meter collector implantado no cluster (Fase 1-3)
- MCP wrapper opcional (Fase 4) para medição sem OTEL

## Acceptance Criteria

1. Qualquer agente setar `OTEL_EXPORTER_OTLP_ENDPOINT=http://agent-meter:3000` e `OTEL_SERVICE_NAME=<agent>` passa a enviar spans
2. Doc cobre todos os 5 agentes com exemplos de ConfigMap/env
3. Smoke script valida pipeline end-to-end
4. Spans aparecem nos reports do dashboard (`top-tools`, `top-mcp-servers`)
