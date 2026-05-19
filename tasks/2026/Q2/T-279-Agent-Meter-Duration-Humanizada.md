# T-279 — Agent Meter: Duração — Formatação Humanizada (ms → s/min)

**Status**: 🆕 Backlog  
**Priority**: 🔵 Medium  
**Owner**: Copilot/VSCode  
**Area**: agent-meter / frontend (dashboard.html)  
**Estimated Effort**: XS (< 1h)

---

## Problema

Valores de duração em todo o dashboard são exibidos em milissegundos brutos:

| Local | Exemplo atual | Esperado |
|-------|--------------|----------|
| Top Tools — Avg Duration | `14267ms` | `14.3s` |
| Top Tools — Avg Duration | `27406ms` | `27.4s` |
| Top Tasks — Total Duration | `123456ms` | `2m 3s` |
| Events tab — Duration | `569ms` | `569ms` ✓ |
| Events tab — Duration | `41030ms` | `41.0s` |

Valores abaixo de ~1000ms estão corretos. O problema é para durações acima de 1s.

---

## Solução

Adicionar função `formatDuration(ms)` em `dashboard.html` e aplicar onde durações são renderizadas.

```js
function formatDuration(ms) {
  if (ms == null || ms === '—') return '—';
  const n = Number(ms);
  if (n < 1000) return n.toFixed(0) + 'ms';
  if (n < 60000) return (n / 1000).toFixed(1) + 's';
  const m = Math.floor(n / 60000);
  const s = Math.round((n % 60000) / 1000);
  return `${m}m ${s}s`;
}
```

### Locais a corrigir

1. **Top Tools** (linha ~1077):
   ```js
   // antes:
   t.avg_duration_ms ? Number(t.avg_duration_ms).toFixed(0) + 'ms' : '—'
   // depois:
   formatDuration(t.avg_duration_ms)
   ```

2. **Top Tasks** (linha ~1088):
   ```js
   // antes:
   t.total_duration_ms ? formatNum(t.total_duration_ms) + 'ms' : '—'
   // depois:
   formatDuration(t.total_duration_ms)
   ```

3. **Events tab** (linha ~1227):
   ```js
   // antes:
   r.duration_ms + 'ms'
   // depois:
   formatDuration(r.duration_ms)
   ```

4. **CSV export** (linha ~1354 e ~1356): manter em ms para compatibilidade de dados

---

## Critérios de Aceite

- [ ] Durações < 1s mostram `NNNms` (sem mudança)
- [ ] Durações 1s–60s mostram `N.Ns`
- [ ] Durações > 60s mostram `Nm Ns`
- [ ] CSV export mantém valores brutos em ms (para análise)
- [ ] Sem regressões visuais nas tabelas

---

## Arquivos a Modificar

- `apps/agent-meter/crates/collector/ui/dashboard.html` (somente)

---

## Notas

Mudança puramente visual/frontend. Requer rebuild Rust (arquivo embutido em `include_str!`), mas é zero-risco funcional.
