# T-314: agent-meter — Trace Export (OpenTelemetry)

## Objetivo

Exportar traces compatíveis com Jaeger/Tempo para integração com sistemas de observabilidade existentes.

## Contexto

O agent-meter já coleta eventos com timestamps e durações. Esta task visa expor esses dados no formato OpenTelemetry para que possam ser consumidos por ferramentas como Jaeger, Tempo, ou Coroot.

## Especificações

### 1. Schema de Trace

Cada trace será composto por:

- **TraceID**: `conversation_id` (agrupa toda a conversa)
- **SpanID**: `event_id` (cada tool call é um span)
- **ParentSpanID**: referência ao span pai (para aninhar tool calls aninhados)
- **Attributes**:
  - `tool.name`
  - `mcp.server`
  - `duration.ms`
  - `tokens.in`
  - `tokens.out`
  - `status` (OK/ERROR)
  - `client.ip`

### 2. Endpoint de Exportação

- **OTLP/gRPC**: `POST /otlp/v1/traces` (padrão OTLP)
- **OTLP/HTTP**: `POST /v1/traces` (alternativo)

### 3. Integração com Collector

- Configurar OTLP receiver no collector
- Exportador para Tempo/Coroot
- Batch processing para eficiência

### 4. UI de Visualização

- Link "View in Jaeger" nos detalhes da conversa
- Filtros por serviço (agent-meter)

## Implementação

### Backend (Rust)

1. Adicionar dependência `opentelemetry` e `opentelemetry-otlp`
2. Criar função `export_trace(conversation_id)` que gera spans
3. Endpoint `/otlp/v1/traces` para recepção de traces (se quiser coletar de outros lugares)
4. Endpoint `/api/traces/:conversation_id` para exportação específica

### Configuração

```yaml
# docker-compose.yml
services:
  agent-meter:
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo:4317
      - OTEL_SERVICE_NAME=agent-meter
```

## Critérios de Aceitação

- [ ] Endpoint OTLP responde corretamente
- [ ] Traces aparecem no Jaeger/Tempo
- [ ] Span attributes contêm todas as informações necessárias
- [ ] Testes de integração com mock do Tempo

## Estimativas

- Backend: 2h
- Testes: 30min
- **Total**: ~2.5h

## Owner

**Copilot/VSCode**

## Status

- [x] Backend: OTLP já implementado em `crates/collector/src/otlp/mod.rs`
- [x] Endpoint `/otlp/v1/traces` já funcional
- [ ] Integração com Tempo/Coroot (configuração)
- [ ] Link "View in Jaeger" na UI

## Notas

- OTLP já está implementado via `handle_trace_request`
- Suporta JSON e protobuf
- Precisa apenas de configuração de exportador para Tempo
