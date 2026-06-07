# T-353: agent-meter — Global search implementation

- **Status**: To Do
- **Priority**: 🔼 High
- **Owner**: Copilot/VSCode
- **Estimate**: 3h

## Context

A barra de busca no topbar está com `disabled` em `dashboard.html:L64-66`:
```html
<input placeholder="Search conversations, models, tools…" disabled>
<span class="kbd">⌘K</span>
```

`conversations.html:L139` tem filtro local (client-side) que filtra rows na tabela —
não é busca global e só funciona nas conversas já carregadas.

**Índices existentes** (migration `20260607000012`): `idx_atc_conversation_started`,
`idx_atc_events_feed`, `idx_atc_repo`, mais índices em agent, model, ide, tool_name, skill, mcp_server.

**Não há endpoint de busca.** `routes/` não tem `search.rs`.

## Arquivos a criar/modificar

| Arquivo | Ação |
|---------|------|
| `src/routes/search.rs` | **CRIAR** — `GET /api/search?q=...` |
| `src/services/search_service.rs` | **CRIAR** — query com ILIKE + agregação |
| `src/routes/mod.rs` | `pub mod search;` |
| `src/services/mod.rs` | `pub mod search_service;` |
| `src/app.rs` | `.merge(routes::search::router())` |
| `ui/dashboard.html` | Remover `disabled`, adicionar JS fetch + dropdown |
| `migrations/` | Opcional: `CREATE EXTENSION pg_trgm` + índice GIN |

## Tasks

- [ ] Criar `search_service.rs` com `search(pool, query, limit)` → busca em user_prompt, tool_name, model, conversation_id via ILIKE
- [ ] Retornar struct `SearchResult { conversation_id, user_prompt, model, agent, started_at, match_field }`
- [ ] Criar `routes/search.rs`: `GET /api/search?q=<query>&limit=20`
- [ ] Registrar em mod.rs + services/mod.rs + app.rs
- [ ] Em `dashboard.html:L64`: remover `disabled`, adicionar `id="globalSearch"`
- [ ] JS: debounce 300ms → `fetch('/api/search?q=...')` → dropdown com resultados clicáveis
- [ ] Cada resultado linka para `/conversations/{id}/timeline`
- [ ] Opcional: migration com `CREATE EXTENSION IF NOT EXISTS pg_trgm` + `CREATE INDEX CONCURRENTLY idx_atc_prompt_trgm ON agent_tool_calls USING gin (user_prompt gin_trgm_ops)`
- [ ] Testar: digitar termo → resultados aparecem em <500ms
