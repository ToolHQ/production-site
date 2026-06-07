# T-353: agent-meter — Global search implementation

- **Status**: To Do
- **Priority**: 🔵 Medium
- **Owner**: Copilot/VSCode
- **Estimate**: 3h

## Context

A barra de busca no topbar está com atributo `disabled` em `dashboard.html` e `app.js`.
Isso é visível para o usuário e passa impressão de produto inacabado.
Deveria buscar conversations por user_prompt, tool_name, model, conversation_id.

## Tasks

- [ ] Criar endpoint `GET /api/search?q=...` no collector
- [ ] Query: `SELECT ... FROM agent_tool_calls WHERE user_prompt ILIKE $1 OR tool_name ILIKE $1 OR model ILIKE $1 OR conversation_id ILIKE $1 LIMIT 20`
- [ ] Adicionar índice GIN trigram se necessário para ILIKE performance
- [ ] Remover `disabled` do search input em `app.js` e `dashboard.html`
- [ ] Implementar dropdown de resultados com links para `/conversations/:id/timeline`
- [ ] Debounce de 300ms no input
