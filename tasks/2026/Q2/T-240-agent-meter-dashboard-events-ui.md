# T-240: agent-meter — Dashboard UI: events feed, model, tokens breakdown

- **Status**: Backlog
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Est.**: 2h
- **Depends-on**: T-239
- **Branch**: `feat/T-240-agent-meter-dashboard-events`

## Context

Com o backend enriquecido pela T-239, o dashboard HTML (`crates/collector/ui/dashboard.html`)
precisa exibir os novos dados. Atualmente:

- Tabela "Top Tools" não mostra modelo, tokens in/out separados, cached tokens
- Não há feed de eventos individuais (só agregações)
- Não há como ver qual conversa ou sessão gerou os calls
- Stats cards mostram apenas total de tokens (sem breakdown in/out/cached)
- Nenhuma coluna de timestamp nas listas

### Referência visual atual
O dashboard tem 3 tabs em "Reports": Top Tools, Top Tasks, Top MCP Servers.
O gráfico "Calls Over Time" filtra por IDE e agent.
Há uma seção "Send Test Event" para debug manual.

## Tasks

### 1. Stats cards — breakdown de tokens
- [ ] Card `TOTAL TOKENS` → split visual: `in: X | out: Y | cached: Z`
  (somar `estimated_input_tokens`, `estimated_output_tokens`, `cached_tokens` da lista de events)
- [ ] Novo card `CACHED TOKENS` com `cached / total` ratio em %
- [ ] Card `AVG TOKENS / CALL` mantém total mas tooltip mostra breakdown

### 2. Top Tools — colunas adicionais
- [ ] Adicionar coluna `TOP MODEL` (vindo de `top_model` do backend T-239)
- [ ] Adicionar colunas `AVG IN TOKENS` e `AVG OUT TOKENS` (separadas, ocultas por padrão em mobile)
- [ ] Adicionar coluna `CACHED TOKENS` total

### 3. Nova aba "Events" no painel Reports
- [ ] Botão/tab "Events" ao lado de "Top Tools / Top Tasks / Top MCP Servers"
- [ ] Tabela paginada consumindo `GET /reports/events`:
  | Colunas | |
  |---|---|
  | `TIMESTAMP` | `started_at` formatado (data hora) |
  | `TOOL` | `tool_name` |
  | `MODEL` | `model` ou `—` |
  | `IN` | `estimated_input_tokens` |
  | `OUT` | `estimated_output_tokens` |
  | `CACHED` | `cached_tokens` |
  | `DURATION` | `duration_ms` + unidade |
  | `STATUS` | ✅/❌ baseado em `ok` |
  | `AGENT` | `agent` |
  | `IDE` | `ide` |
  | `IP` | `client_ip` (truncado) |
- [ ] Paginação: botões Anterior / Próximo (offset-based, limit=50)
- [ ] Filtro por `conversation_id` (input de texto)

### 4. Filtro de modelo no gráfico Calls Over Time
- [ ] Dropdown `model` ao lado dos dropdowns `ide` e `agent`
- [ ] Passar `?model=gpt-4o` na query do `/reports/calls-over-time`
  (requer que o endpoint aceite o filtro — coordenar com T-239 backend)

### 5. Atualização do exportador CSV
- [ ] Incluir novos campos (`model`, `cached_tokens`, `conversation_id`) no CSV de Top Tools

### 6. Responsive + dark mode
- [ ] Colunas extras da tabela Events ocultadas em viewport < 768px
- [ ] Cores coerentes com o dark theme existente

## Acceptance Criteria
- Tab "Events" exibe lista paginada com model, tokens breakdown, timestamp, IP
- Stats cards mostram breakdown in/out/cached
- Top Tools tem coluna TOP MODEL preenchida após span real do Copilot
- Dashboard carrega sem erros no console
- Mobile (< 768px): tabela Events mostra apenas TIMESTAMP, TOOL, MODEL, STATUS
