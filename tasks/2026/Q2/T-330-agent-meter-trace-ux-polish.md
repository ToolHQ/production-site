# T-330 — agent-meter: Trace UX Polish

**Epic**: SaaS Revenue → Trace Visualization  
**Priority**: 🔵 Medium  
**Owner**: Copilot/VSCode  
**Est.**: 2h  
**Depende de**: nenhuma (pure frontend)

---

## Contexto

Melhorias de ergonomia que fazem o trace parecer um produto premium vs um MVP —
sem nenhuma mudança de schema ou backend.

---

## 1. Navegação por teclado

```javascript
document.addEventListener("keydown", (e) => {
  if (e.target.tagName === "INPUT") return; // não interceptar search

  const cur = state.selected ? state.filtered.indexOf(state.selected) : -1;

  if (e.key === "j" || e.key === "ArrowDown") {
    e.preventDefault();
    selectEvent(state.filtered[Math.min(cur + 1, state.filtered.length - 1)]);
    scrollSpanIntoView();
  }
  if (e.key === "k" || e.key === "ArrowUp") {
    e.preventDefault();
    selectEvent(state.filtered[Math.max(cur - 1, 0)]);
    scrollSpanIntoView();
  }
  if (e.key === "Escape") closeDrawer();
  if (e.key === "e" && state.selected) exportSelectedSpan();
});
```

## 2. Deep link por span

URL: `/conversations/:id/timeline?span=42`

```javascript
// Na carga da página, após loadTimeline():
const spanParam = new URLSearchParams(location.search).get("span");
if (spanParam) {
  const ev = state.events.find((e) => e.order == spanParam);
  if (ev) {
    selectEvent(ev);
    scrollSpanIntoView();
  }
}

// Ao selecionar span, atualizar URL sem reload:
function selectEvent(e) {
  history.replaceState({}, "", `?span=${e.order}`);
  // ... resto do código atual
}
```

## 3. Copy-as-JSON no drawer

Botão no header do drawer:

```html
<button class="am-btn am-btn-ghost am-btn-xs" onclick="copySpanJson()">
  <svg class="am-icon-sm"><use href="/_static/icons.svg#i-copy" /></svg>
  Copy JSON
</button>
```

```javascript
function copySpanJson() {
  navigator.clipboard.writeText(JSON.stringify(state.selected, null, 2));
  // feedback visual: botão muda para "Copied ✓" por 1.5s
}
```

## 4. Live tail (auto-refresh para conversas ativas)

Detectar conversa ativa: `ended_at` é recente (< 30s) ou `event_count` cresceu.

```javascript
let liveTailInterval = null;

function startLiveTail() {
  liveTailInterval = setInterval(async () => {
    const prev = state.data.event_count;
    await loadTimeline({ silent: true }); // não resetar zoom/seleção
    if (state.data.event_count !== prev) {
      // novo evento: scroll to bottom, atualizar minimap
      scrollToLatest();
    }
    // parar se conversa terminou (ended_at > 60s atrás)
    if (isConversationComplete()) stopLiveTail();
  }, 5000);
}
```

Toggle no toolbar:

```html
<label><input type="checkbox" id="liveTail" /> Live tail</label>
```

Auto-ativar se `conversação iniciada < 5min && ainda chegando eventos`.

## 5. Indicator de span count no título da janela

```javascript
document.title = `${data.event_count} events · ${data.title} · agent-meter`;
```

## 6. Breadcrumb de conversação no back-link

```html
<a href="/conversations" class="am-btn am-btn-ghost am-btn-sm">
  ← All conversations
</a>
```

(substituir o botão "Dashboard" atual que é confuso)

## Acceptance Criteria

- [ ] `j`/`k` navega entre spans; seleção ativa scrolla para estar visível
- [ ] `Escape` fecha drawer
- [ ] `?span=N` na URL abre drawer no span correto ao carregar
- [ ] Selecionar span atualiza URL (sem recarregar)
- [ ] Copy JSON funciona + feedback visual "Copied ✓"
- [ ] Toggle live tail funcional com auto-refresh a cada 5s
- [ ] Live tail para automaticamente quando conversa encerra
- [ ] `document.title` mostra contagem de eventos
- [ ] Back-link leva para `/conversations` (não dashboard)
- [ ] Zero regressões no waterfall existente

## Notas

- `scrollSpanIntoView()`: calcular `y = TOP_PAD + idx * ROW_H` e usar
  `waterfall.scrollTo({ top: y - ROW_H*3, behavior: 'smooth' })`
- Live tail deve preservar zoom, filtros e span selecionado
