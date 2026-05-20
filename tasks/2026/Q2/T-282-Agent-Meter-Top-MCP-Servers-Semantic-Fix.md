# T-276 — Agent Meter: Top MCP Servers — Correção Semântica

**Status**: 🆕 Backlog  
**Priority**: 🔼 High  
**Owner**: Copilot/VSCode  
**Area**: agent-meter / backend + frontend  
**Estimated Effort**: S (< 2h)

---

## Problema

A aba "Top MCP Servers" exibe provedores LLM (anthropic, openai) **como se fossem MCP servers**, o que é semanticamente incorreto.

### Root Cause (confirmada por auditoria)

No OTLP ingestion (`otlp/mod.rs`), spans de LLM (`llm_chat`) populam o campo `mcp_server` com o nome do provedor:

```rust
// Use gen_ai.system as mcp_server equivalent for LLM provider grouping
let mcp_server = system.or_else(|| {
    model.as_ref().map(|m| {
        if m.contains("claude") { "anthropic".to_string() }
        else if m.contains("gpt") { "openai".to_string() }
        ...
    })
});
```

A query `top-mcp-servers` faz `WHERE mcp_server IS NOT NULL` sem excluir `tool_name = 'llm_chat'`, portanto retorna ambos.

### Sintomas Observados

- Tab "Top MCP Servers" mostra: anthropic (62 calls, 4.7M tokens), openai (13 calls, 20k tokens)
- Coluna "Avg Resp Bytes" sempre `—` (nulos para llm_chat events)
- KPI "MCP Servers = 2" contabiliza os provedores LLM, não servidores MCP reais (filesystem, playwright, etc.)
- Os verdadeiros MCP servers (se existirem) estão misturados com LLM providers

---

## Solução Proposta

### Opção A — Fix mínimo (recomendada): Excluir `llm_chat` da query

Em `report_service.rs`, na função `top_mcp_servers()`, adicionar condição:

```sql
AND tool_name != 'llm_chat'
```

Isso faz a aba mostrar apenas chamadas reais de ferramentas MCP.
Os dados de LLM provider (anthropic/openai) **já estão** visíveis na aba "Top Tools" → coluna "Provider".

### Opção B — Reestruturar (mais trabalho)

Adicionar um campo `llm_provider` separado no schema, separando o conceito de "provedor LLM" de "MCP server". Requer migração de schema.

**Recomendação**: Opção A agora, Opção B numa sprint futura.

---

## Arquivos a Modificar

1. `apps/agent-meter/crates/collector/src/services/report_service.rs`
   - Função `top_mcp_servers()` → adicionar `AND tool_name != 'llm_chat'`

2. (Opcional) `apps/agent-meter/crates/collector/ui/dashboard.html`
   - KPI label "MCP Servers" → manter (agora vai mostrar contagem correta)
   - Possível: adicionar tooltip explicando que mostra servidores de ferramentas, não LLMs

---

## Critérios de Aceite

- [ ] Tab "Top MCP Servers" NÃO mostra mais anthropic/openai
- [ ] KPI "MCP Servers" reflete a contagem real de tool servers únicos (pode ser 0 se nenhum span MCP foi recebido)
- [ ] "Avg Resp Bytes" mostra valor quando existe (para ferramentas com `response_bytes` preenchido)
- [ ] Aba "Top Tools" ainda mostra llm_chat com Provider = anthropic/openai (não afetada)
- [ ] Deploy + smoke test confirmado

---

## Contexto Adicional

- Auditoria realizada em 2025-07-14 via Playwright no dashboard https://agent-meter.dnor.io/
- Dados atuais no cluster: apenas llm_chat events de OTLP chegam com `mcp_server` preenchido; nenhum span de MCP tool real (`mcp.server.name`) foi detectado nos últimos 6h
- Após o fix, a aba pode ficar "No data yet" se nenhum agente estiver enviando spans de ferramentas MCP — isso é o comportamento **correto**
