# T-313: agent-meter — Conversation Timeline View

## Objetivo

Criar uma visualização de timeline para interações de chats/sessões, agrupando tool calls por `conversation_id` e exibindo de forma clara a sequência de ações e seu impacto.

## Contexto

O agent-meter coleta eventos de tool calls com metadados como:

- `conversation_id` (agrupa interações relacionadas)
- `tool_name`, `mcp_server`, `duration`, `tokens_in/out`, `ok`, `started_at`, `ended_at`

Atualmente, os reports são tabulares e focados em agregação. Esta task visa criar uma experiência de "replay" de sessões.

## Especificações

### 1. Backend API

- **Endpoint**: `GET /api/conversations/:conversation_id/timeline`
- **Response**:

```json
{
  "conversation_id": "uuid",
  "title": "Resumo da conversa (primeiros 50 chars do prompt)",
  "started_at": "ISO8601",
  "ended_at": "ISO8601",
  "total_duration_ms": 12345,
  "total_tokens_in": 15000,
  "total_tokens_out": 25000,
  "events": [
    {
      "order": 1,
      "tool_name": "read_file",
      "mcp_server": "filesystem",
      "duration_ms": 45,
      "tokens_in": 0,
      "tokens_out": 1200,
      "ok": true,
      "started_at": "ISO8601",
      "ended_at": "ISO8601"
    }
  ]
}
```

### 2. Frontend UI

- **Nova página**: `/conversations/:id`
- **Componentes**:
  - Header: título da conversa, duração total, custo estimado
  - Timeline vertical com:
    - Timestamps relativos (ex: "+2.3s")
    - Ícones por tipo de tool
    - Status (✅ sucesso, ❌ erro)
    - Tooltip com detalhes ao hover
  - Sidebar: resumo estatístico (total tools, erros, models usados)

### 3. Filtros

- Por data (range)
- Por modelo (se disponível)
- Por cliente IP
- Por IDE/Agente

### 4. Exportação

- Botão "Export JSON" para baixar timeline completa
- Botão "Export CSV" para análise externa

## Implementação

### Backend (Rust - collector crate)

1. Adicionar endpoint `/conversations/:id/timeline`
2. Query SQL otimizada para buscar events ordenados por `started_at`
3. Calcular agregados (duração total, tokens, custo)

### Frontend (React/TypeScript)

1. Criar página `ConversationTimeline`
2. Componente `TimelineView` com virtualização (se muitos events)
3. Integração com API existente

## Critérios de Aceitação

- [ ] Endpoint `/api/conversations/:id/timeline` retorna dados corretos
- [ ] Página `/conversations/:id` carrega sem erros
- [ ] Timeline exibe events em ordem cronológica
- [ ] Filtros funcionam corretamente
- [ ] Exportação JSON/CSV funcional
- [ ] Testes unitários para cálculo de agregados

## Estimativas

- Backend: 2h
- Frontend: 2h
- Testes: 30min
- **Total**: ~4h

## Owner

**Copilot/VSCode**

## Status

- [x] Backend: Modelo `timeline.rs` criado
- [x] Backend: Service `conversation_service.rs` com queries SQL
- [x] Backend: Rota `/conversations/:conversation_id/timeline` registrada
- [x] Backend: Rota `/conversations/:conversation_id` (UI) criada
- [x] Build: `cargo check --lib` passando
- [x] Frontend: Página `timeline.html` criada com timeline visual
- [x] Deploy: Imagem buildada e deployado com sucesso
- [x] Testes: Endpoints testados e funcionais
  - `GET /conversations/:id/timeline` → JSON com timeline
  - `GET /conversations/:id` → HTML com UI

## Testes Realizados

```bash
# Health check (local)
curl http://localhost:3000/health
# {"service":"agent-meter-collector","status":"ok"}

# Timeline API (local)
curl http://localhost:3000/conversations/test-id/timeline
# {"conversation_id":"test-id","title":"...","events":[],...}

# Timeline UI (local)
curl http://localhost:3000/conversations/test-id
# <!DOCTYPE html>... (timeline.html)

# Health check (público)
curl https://agent-meter.dnor.io/health
# {"service":"agent-meter-collector","status":"ok"}

# Timeline API (público)
curl https://agent-meter.dnor.io/conversations/test-public/timeline
# {"conversation_id":"test-public","title":"...","events":[]}
```

## Acesso Público

- **Health**: https://agent-meter.dnor.io/health
- **Timeline API**: https://agent-meter.dnor.io/conversations/:id/timeline
- **Timeline UI**: https://agent-meter.dnor.io/conversations/:id
