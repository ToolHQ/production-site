# T-281 — Agent Meter: Colunas Ordenáveis nos Reports

**Status**: 🆕 Backlog  
**Priority**: 🟡 Low  
**Owner**: Copilot/VSCode  
**Area**: agent-meter / frontend (dashboard.html)  
**Estimated Effort**: M (2–4h)

---

## Problema

As tabelas dos reports (Top Tools, Top Conversations, Top MCP Servers) não têm ordenação interativa. O usuário não pode clicar em um header de coluna para ordenar por:
- Calls (decrescente → crescente)
- Tokens
- Duration
- Error Rate
- etc.

A ordenação atual é sempre `ORDER BY calls DESC` hardcoded no backend.

---

## Solução Proposta

### Implementação client-side (recomendada para primeira versão)

Adicionar sort client-side no JS do dashboard, sem necessidade de mudanças no backend.

```js
// Ao clicar em um <th>, ordenar o array state.data[tab] por aquela coluna
// Alternar asc/desc a cada clique
// Re-renderizar a tabela

function sortTable(tab, colIdx, direction) {
  const colKeys = tabColumnKeys[tab]; // mapeamento colIdx → field name
  const field = colKeys[colIdx];
  state.data[tab].sort((a, b) => {
    const av = Number(a[field]) || 0;
    const bv = Number(b[field]) || 0;
    return direction === 'asc' ? av - bv : bv - av;
  });
  renderTab(tab);
}
```

### Indicadores visuais

- Header clicável: `cursor: pointer`, hover com `background` diferenciado
- Seta ↑/↓ ao lado do header ativo
- Manter estado de sort no `state` para persistir ao mudar de tab

### Colunas sortáveis por tab

**Top Tools**: Calls ✓, Avg In ✓, Avg Out ✓, Cached ✓, Avg Duration ✓, Errors ✓ (Type e Tool não fazem sentido como sort numérico — usar alfabético)

**Top Conversations** (ex-Tasks): Tool Calls ✓, Total Tokens ✓, Total Duration ✓, Errors ✓, Distinct Tools ✓

**Top MCP Servers**: Calls ✓, Total Tokens ✓, Avg Resp Bytes ✓, Error Rate ✓

---

## Arquivos a Modificar

- `apps/agent-meter/crates/collector/ui/dashboard.html` (somente)
  - `buildTable()` → adicionar atributo `data-sortcol` nos `<th>`
  - Handler de click no `<th>` → chamar `sortTable()`
  - CSS → estilo de header clicável e indicador de sort

---

## Critérios de Aceite

- [ ] Clicar em header numérico ordena a tabela (desc primeiro, depois asc)
- [ ] Segundo clique inverte a direção
- [ ] Indicador visual (seta ↑↓) mostra coluna e direção ativas
- [ ] Funciona em Top Tools, Top Conversations e Top MCP Servers
- [ ] Sem regressões no comportamento de filtros e tabs
- [ ] Sort não persiste após mudar o time range (nova fetch reseta a ordenação — OK)
