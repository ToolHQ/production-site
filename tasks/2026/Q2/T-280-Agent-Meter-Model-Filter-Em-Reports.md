# T-280 — Agent Meter: Filtro "model" Global Não Afeta Reports

**Status**: 🆕 Backlog  
**Priority**: 🔵 Medium  
**Owner**: Copilot/VSCode  
**Area**: agent-meter / backend + frontend  
**Estimated Effort**: M (2–3h)

---

## Problema

O filtro `filterModel` na barra global (junto com filterIde e filterAgent) parece funcionar visualmente — o select muda — mas **não afeta os dados dos reports** (Top Tools, Top Conversations, Top MCP Servers).

O comentário no próprio código confirma:
```js
// model filter not yet supported server-side on top-tools/tasks — skip for reports
```

O filtro de model **só afeta** o tab Events (via a query de events que suporta `model=` no querystring).

### Impacto

- Usuário seleciona "claude-sonnet-4-6" no filtro global, vai para "Top Tools" → vê TODOS os tools (incluindo gpt-4o-mini), não apenas os do modelo selecionado
- UX enganosa: o elemento de UI promete um comportamento que não existe

---

## Solução Proposta

### Opção A — Implementar model filter no backend (completa)

1. **Backend** (`report_service.rs`): adicionar parâmetro `model` nos filtros de cada report query:
   ```sql
   AND ($N::text IS NULL OR model = $N)
   ```
   Requer que o campo `model` exista em `agent_tool_calls` (verificar schema).

2. **Frontend** (`dashboard.html`): remover o comentário e passar `model` no `buildQuery()`:
   ```js
   if (f.model) q += `&model=${encodeURIComponent(f.model)}`;
   ```

### Opção B — Indicar visualmente que model filter é apenas para Events (mínimo)

1. Desabilitar o `filterModel` select quando não estiver na aba Events
2. OU adicionar tooltip/nota: "Filtro de modelo disponível apenas na aba Events"

### Opção C — Mover filterModel para dentro da aba Events

Deixar filterIde e filterAgent como filtros globais (que funcionam nos reports via backend), e mover filterModel para o painel de filtros da aba Events apenas.

**Recomendação**: Opção A (implementar corretamente), com Opção B como correção de curto prazo.

---

## Pré-requisito

Verificar se coluna `model` existe em `agent_tool_calls`. Se não, a Opção A requer migração de schema.

```sql
\d agent_tool_calls  -- verificar colunas
```

---

## Arquivos a Modificar

1. `apps/agent-meter/crates/collector/src/services/report_service.rs`
   - Adicionar `model` em `ReportQuery` struct
   - Adicionar filtro `AND model = $N` em todas as queries de report

2. `apps/agent-meter/crates/collector/ui/dashboard.html`
   - `buildQuery()` → incluir `model` no querystring quando selecionado

---

## Critérios de Aceite

- [ ] Selecionar "claude-sonnet-4-6" no filterModel → Top Tools mostra apenas rows onde `top_model = 'claude-sonnet-4-6'`
- [ ] Filtro funciona combinado com filterIde e filterAgent
- [ ] Comportamento correto em todos os 4 tabs (Tools, Conversations, MCP Servers, Events)
- [ ] "all models" limpa o filtro corretamente
