# T-329 — agent-meter: Trace Statistics Panel

**Epic**: SaaS Revenue → Trace Visualization  
**Priority**: 🔼 High  
**Owner**: Copilot/VSCode  
**Est.**: 3h  
**Depende de**: nenhuma (computa client-side com dados já disponíveis)

---

## Contexto

Datadog mostra um painel de estatísticas ao lado do trace: P50/P95/P99 de latência,
breakdown por tipo de operação, token efficiency. No agent-meter, o summary atual
tem apenas totais. Este task adiciona uma aba "Stats" no painel lateral do timeline.

---

## UI — Aba Stats

O drawer lateral ganha duas abas: **Event** (detalhe do span selecionado, atual) e
**Stats** (estatísticas da conversa inteira):

```
┌─ Event ─┬─ Stats ─┐
│                   │
│  LATENCY          │
│  P50    1.2s      │
│  P95    8.4s      │
│  P99    14.2s     │
│  Max    21.5s     │
│  Avg    3.1s      │
│                   │
│  BY CATEGORY      │
│  llm   ████ 62%  14.2s  $21.50 │
│  tool  ██   28%   6.4s   $0.12 │
│  shell █     7%   1.6s   —     │
│  fs    █     3%   0.7s   —     │
│                   │
│  TOKEN EFFICIENCY │
│  In    45.2K      │
│  Out   12.1K      │
│  Ratio 3.7:1      │
│  $/1K tok $0.014  │
│                   │
│  DISTRIBUTION     │
│  [histograma SVG  │
│   de duração ms]  │
└───────────────────┘
```

## Cálculos (client-side JavaScript)

```javascript
function computeStats(events) {
  const durations = events.map((e) => e.duration_ms).sort((a, b) => a - b);
  const n = durations.length;
  return {
    p50: durations[Math.floor(n * 0.5)],
    p95: durations[Math.floor(n * 0.95)],
    p99: durations[Math.floor(n * 0.99)],
    max: durations[n - 1],
    avg: durations.reduce((s, v) => s + v, 0) / n,
    byCategory: groupByCategory(events), // duration sum + cost sum + count
    tokenEfficiency: computeTokenRatio(events),
    histogram: buildHistogram(durations, 20), // 20 buckets
  };
}
```

## Histograma SVG

Mini histograma de 20 barras mostrando distribuição de duração:

- Eixo X: range de ms (log scale para spans com outliers)
- Eixo Y: contagem
- Hover: "X eventos entre Yms–Zms"
- Altura: 60px, largura: 100% do painel

## Stats sempre visíveis (fora do drawer)

Adicionar uma linha de estatísticas condensadas no `summary` do topo da página:

```
Duration: 32.4s  |  P95: 8.4s  |  llm: 62%  |  Token ratio: 3.7:1  |  $/1K: $0.014
```

## Acceptance Criteria

- [ ] Aba "Stats" no drawer funcional
- [ ] P50/P95/P99/Max/Avg calculados corretamente
- [ ] Breakdown por categoria com mini barras
- [ ] Token efficiency ratio + custo por 1K tokens
- [ ] Histograma SVG de distribuição de duração
- [ ] Stats condensadas na linha do summary (topo da página)
- [ ] Atualiza ao aplicar filtros (errors only, text filter)
- [ ] Funciona com 0 eventos (estado vazio gracioso)

## Notas

- Quando T-326 estiver em prod, adicionar stats por profundidade (depth 0 vs 1 vs 2+)
- P99 com < 100 eventos pode ser misleading — mostrar nota "n=X" no tooltip do percentil
