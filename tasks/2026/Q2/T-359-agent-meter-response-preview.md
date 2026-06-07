# T-359: agent-meter — Conversation response_preview population

- **Status**: To Do
- **Priority**: 🔵 Medium
- **Owner**: Copilot/VSCode
- **Estimate**: 2h

## Context

A API `/api/conversations` retorna `response_preview: null` para a maioria das conversas.
Este campo deveria mostrar um preview da resposta do LLM (primeiros ~200 chars).
Na conversations list, ajuda o usuário a identificar rapidamente do que trata cada conversa.

## Tasks

- [ ] No OTLP ingestion: extrair `gen_ai.completion` ou response body truncado
- [ ] Salvar em `tool_result` ou nova coluna `response_preview` na `agent_tool_calls`
- [ ] Na query de conversations: popular `response_preview` do primeiro evento com resposta
- [ ] Truncar a 200 chars para não poluir a API
- [ ] Testar: nova conversa via Copilot CLI → response_preview aparece na API
