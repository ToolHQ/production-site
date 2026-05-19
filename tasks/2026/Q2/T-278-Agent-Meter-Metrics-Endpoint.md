# T-278 — Agent Meter: Endpoint /metrics — 404 Not Found

**Status**: 🆕 Backlog  
**Priority**: 🔵 Medium  
**Owner**: Copilot/VSCode  
**Area**: agent-meter / backend  
**Estimated Effort**: S (1–2h)

---

## Problema

O footer do dashboard contém um link "Metrics" apontando para `/metrics`, mas o endpoint retorna **404**.

```
GET https://agent-meter.dnor.io/metrics → 404
```

O endpoint `/health` funciona corretamente (200 + JSON). O `/metrics` está referenciado no frontend mas não implementado no Axum router.

---

## Solução Proposta

### Opção A — Implementar endpoint Prometheus (recomendada)

Expor métricas básicas no formato Prometheus para que Coroot/Prometheus possa scrape:

```
# HELP agent_meter_events_total Total tool call events received
# TYPE agent_meter_events_total counter
agent_meter_events_total{tool="llm_chat",ide="copilot-vscode"} 1234
...
```

Métricas mínimas úteis:
- `agent_meter_events_total` (counter por tool_name, ide, agent)
- `agent_meter_errors_total` (counter por tool_name)
- `agent_meter_tokens_total` (counter por tipo: input, output, cached)
- `agent_meter_duration_seconds` (histogram por tool_name)

Integração com Coroot existente no cluster.

### Opção B — Remover link do footer (mínimo)

Se não há tempo para implementar métricas Prometheus, simplesmente remover o link do footer ou trocar por algo útil (ex: link para o dashboard Coroot).

**Recomendação**: Opção B imediata (1 linha de HTML), Opção A na próxima sprint de features.

---

## Arquivos a Modificar

**Opção B (mínimo):**
- `apps/agent-meter/crates/collector/ui/dashboard.html` → remover/substituir link `/metrics` no footer

**Opção A (completa):**
- `apps/agent-meter/crates/collector/src/routes/` → criar `metrics.rs` com handler Prometheus
- `apps/agent-meter/crates/collector/src/routes/mod.rs` → registrar rota `/metrics`
- `Cargo.toml` → adicionar crate `prometheus` ou `metrics-exporter-prometheus`

---

## Critérios de Aceite

- [ ] GET /metrics não retorna 404
- [ ] (Opção A) Resposta no formato Prometheus text exposition format
- [ ] (Opção A) Coroot consegue fazer scrape da rota
- [ ] (Opção B) Footer não contém link morto para /metrics

---

## Referências

- `/health` implementado em `apps/agent-meter/crates/collector/src/routes/health.rs`
- Footer HTML no `dashboard.html` (~linha 107–128)
