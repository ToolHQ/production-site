# T-203 — Node Fleet: Fix Tooltip Balloon Positioning

**Status**: ✅ Done
**Owner**: Copilot/VSCode
**Priority**: 🔼 High
**Estimate**: 1h
**Created**: 2026-05-16
**Closed**: 2026-05-16

## Problema

Os balões de hover da tabela Node Fleet (CPU / Memory / Disk) usam `position: absolute; bottom: calc(100% + 12px)` para aparecer acima da célula. Porém, a tabela tem ancestrais com `overflow: hidden` ou restrições de stacking context que fazem o balão ser cortado ou aparecer na posição errada — sobreposição com o cabeçalho da seção.

Screenshot: balão de "Memory: 4.1 GiB / 5.8 GiB" e "Recent History" visivelmente cortando o header "UTILIZATION".

## Root Cause

`position: absolute` com `bottom: calc(100% + 12px)` posiciona o card acima da célula. Quando a linha está no topo da viewport, o card vai além dos limites do painel e entra no espaço do header fixo. `overflow: visible !important` no `.table-shell` não é suficiente porque há outros ancestrais com `overflow: hidden`.

## Fix

Substituir `position: absolute` por `position: fixed` com coordenadas computadas via JavaScript (`getBoundingClientRect()`):

- Criado componente `TooltipWrapper` em `NodesPanel.tsx` com `useState` + `useRef` de Preact hooks
- No `onMouseEnter`: calcula `rect.bottom + 8px` (abaixo da célula) + `rect.left + rect.width/2` (centro horizontal)
- Renderiza o card com `position: fixed` e coordenadas inline — imune a qualquer overflow/clipping
- Seta (arrow) invertida: aponta para CIMA (em direção à célula acima do card)
- CSS simplificado: removida a regra `:hover .node-cell-tooltip-card { display: block }` (JS controla)

## Validação

- [ ] Hover em CPU, Memory, Disk mostra card abaixo da célula sem clipping
- [ ] Card não sobrepõe header ao passar o mouse nas primeiras linhas
- [ ] Sparklines visíveis
- [ ] Valores absolutos legíveis
- [ ] Deploy validado em prod
