# T-327 — agent-meter: Gap Analysis + Critical Path

**Epic**: SaaS Revenue → Trace Visualization  
**Priority**: 🔼 High  
**Owner**: Copilot/VSCode  
**Est.**: 3h  
**Depende de**: nenhuma (pure frontend, dados já disponíveis)

---

## Contexto

Dois recursos de diagnóstico que Datadog/Jaeger oferecem e que são pure-frontend
(não requerem mudanças de schema):

1. **Gap Analysis**: mostrar barras cinzas entre eventos representando "idle time"
   (tempo em que o agente não estava fazendo nada). Crucial para detectar throttling,
   rate limits e latência de rede entre calls.

2. **Critical Path**: destacar em laranja a cadeia de eventos sequenciais que somam
   o maior tempo total — a "rota crítica" que determina a duração total da conversa.

---

## Gap Analysis

### Lógica
```javascript
// Após ordenar eventos por startMs, calcular gaps
for (let i = 1; i < events.length; i++) {
  const gapMs = events[i].startMs - events[i-1].endMs;
  if (gapMs > 50) { // ignorar gaps < 50ms (overhead normal)
    gaps.push({ startMs: events[i-1].endMs, endMs: events[i].startMs, durationMs: gapMs });
  }
}
```

### Renderização
- Barra cinza (`var(--am-text-dim)` com opacity 0.25) na linha i-0.5 do waterfall
- Altura: 6px (mais fina que barras normais de 14px)
- Tooltip: "⏸ Idle · Xms"
- Toggle no toolbar: `<label><input type="checkbox" id="showGaps"> Show idle gaps</label>`

## Critical Path

### Lógica
```javascript
// Critical path: sequência de spans não-sobrepostos com maior soma de duração
// Greedy: pega o próximo span que começa após o fim do atual e tem maior duration
function computeCriticalPath(events) {
  let path = [], cursor = 0;
  let sorted = [...events].sort((a,b) => b.duration_ms - a.duration_ms);
  // DP simples: O(n²) aceitável para 2000 eventos
  // ...retorna array de índices no critical path
}
```

### Renderização
- Spans no critical path ganham `stroke: var(--am-accent); stroke-width: 2` na barra
- Label "CRITICAL" em badge laranja no header da linha
- Métrica no summary: "Critical path: 14.2s (62% do total)"
- Toggle: `<label><input type="checkbox" id="showCritical"> Critical path</label>`

## Coluna "% do total" por span

No drawer (painel lateral de detalhe do span), adicionar:
```
% of total   31.2%  ████████░░░░░░░░░░░░
```
Mini progress bar visual.

## Acceptance Criteria

- [ ] Toggle "Show idle gaps" funcional (default: off)
- [ ] Gaps com > 50ms renderizados como barras cinzas na timeline
- [ ] Tooltip de gap mostra duração formatada
- [ ] Toggle "Critical path" funcional (default: off)
- [ ] Spans do critical path com borda destacada
- [ ] Badge "CRITICAL" no label da linha
- [ ] Summary mostra "Critical path: Xs (Y%)"
- [ ] Coluna % no drawer
- [ ] Tudo togglável — zero impacto visual quando desligado
- [ ] Performance não degradada

## Notas

- Critical path é intuitivo para o usuário: "por que minha sessão de 20min foi
  a mais lenta?" — sem precisar de spans aninhados (T-326)
- Gap analysis imediatamente útil para detectar rate limiting da API OpenAI/Anthropic
