# T-328 — agent-meter: Flame Graph View

**Epic**: SaaS Revenue → Trace Visualization  
**Priority**: 🔼 High  
**Owner**: Copilot/VSCode  
**Est.**: 4h  
**Depende de**: T-326 (nesting torna o flame graph mais rico; mas funciona flat também)

---

## Contexto

O flame graph é o modo de visualização mais usado para profiling em Brendan Gregg style,
Perfetto, Chrome DevTools e Datadog. Mostra blocos proporcionais onde:

- Largura = % do tempo total
- Empilhamento = hierarquia de chamadas (ou agrupamento por categoria)
- Cores = categoria (llm/fs/shell/tool)

É especialmente útil para responder "onde está indo meu budget de tempo/custo?".

---

## Toggle de View

No toolbar do timeline, adicionar toggle:

```html
<div class="am-btn-group">
  <button class="am-btn am-btn-ghost am-btn-sm active" id="btnViewWaterfall">
    <svg>…i-waterfall…</svg> Waterfall
  </button>
  <button class="am-btn am-btn-ghost am-btn-sm" id="btnViewFlame">
    <svg>…i-flame…</svg> Flame
  </button>
</div>
```

## Flame Graph — Modo Flat (sem nesting)

Quando T-326 não estiver disponível, agrupa por `category`:

```
┌─────────────────────────────────────────────────────────────────┐
│ llm     ████████████████████████████████  62%   14.2s  $21.50  │
│ tool    ██████████████  28%   6.4s   $0.12                      │
│ shell   ████  7%    1.6s   —                                     │
│ fs      ██  3%    0.7s   —                                       │
└─────────────────────────────────────────────────────────────────┘
```

Click na categoria → expande mostrando top-N tools dentro daquela categoria:

```
▾ llm  ████████████████████████████████  62%
  claude-sonnet-4-6  ██████████████████  54%
  gpt-4o-mini        █████  8%
```

## Flame Graph — Modo Nested (com T-326)

Com spans aninhados disponíveis, renderizar como stacked flame:

```
Row 0 (depth 0): [      llm_chat · 4.6s       ][  llm_chat · 2.1s  ]
Row 1 (depth 1):   [read][grep][replace]          [run_terminal]
Row 2 (depth 2):
```

- Cada linha é uma "profundidade" do trace
- Click em bloco → abre drawer (mesmo do waterfall)
- Hover → tooltip igual ao waterfall

## SVG Rendering

```javascript
function renderFlame(events, totalMs) {
  const W = container.clientWidth;
  const ROW_H = 28;

  // Group by category first
  const byCategory = groupBy(events, (e) => e.category);
  let y = 0;
  for (const [cat, evs] of Object.entries(byCategory)) {
    const pct = evs.reduce((s, e) => s + e.duration_ms, 0) / totalMs;
    const w = pct * W;
    // render block + label + click handler
    y += ROW_H;
  }
}
```

## Acceptance Criteria

- [ ] Toggle Waterfall ↔ Flame funcional, estado persistido em `sessionStorage`
- [ ] Flame flat mostra agrupamento por categoria com % + duração + custo
- [ ] Click em categoria expande top tools dentro dela
- [ ] Hover tooltip consistente com waterfall
- [ ] Click em bloco de tool abre drawer
- [ ] Legenda atualizada para modo flame
- [ ] Zoom/filter do waterfall não afeta flame (states independentes)
- [ ] Responsive: funciona em viewport 768px+

## Notas

- Implementar modo flat primeiro (T-326 não bloqueante)
- Modo nested pode ser feature flag ativado quando T-326 estiver em prod
- Referência visual: https://www.brendangregg.com/flamegraphs.html
