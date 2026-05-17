# T-225 — agent-meter: OTEL integration + multi-agent docs

**Owner**: OpenCode
**Priority**: 🔼 High
**Estimate**: 2h
**Status**: ✅ Done

## Goal

Document and implement how all agents (OpenCode, Cursor, Copilot/VSCode, Antigravity, Codex) send OTEL traces to the agent-meter collector, and create a central reference doc.

## Tasks

- [x] Implementar suporte OTEL no collector (Fase 3) — `tracing_opentelemetry::layer()`, upgrade 0.25→0.26, zero-crash sem endpoint
- [x] `docs/agent-meter-otel.md` criado — arquitetura, env vars por agente, CLI/curl exemplos, OTEL config
- [x] `scripts/smoke-otel.sh` criado — valida pipeline end-to-end (health → task start → event POST → reports → task end)
- [x] ConfigMap `agent-meter-otel` adicionado ao `k8s/agent-meter.yaml` com `otel_exporter_otlp_endpoint` e `otel_service_name`
- [x] Env vars no Deployment usam `configMapKeyRef` com `optional: true` — zero-crash se ConfigMap não existir

## Dependencies

- agent-meter collector implantado no cluster (Fase 1-3)
- MCP wrapper opcional (Fase 4) para medição sem OTEL

## Acceptance Criteria

1. Qualquer agente setar `OTEL_EXPORTER_OTLP_ENDPOINT=http://agent-meter:3000` e `OTEL_SERVICE_NAME=<agent>` passa a enviar spans
2. Doc cobre todos os 5 agentes com exemplos de ConfigMap/env
3. Smoke script valida pipeline end-to-end
4. Spans aparecem nos reports do dashboard (`top-tools`, `top-mcp-servers`)
