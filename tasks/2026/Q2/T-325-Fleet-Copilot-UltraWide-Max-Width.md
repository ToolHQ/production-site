# T-325: Fleet Copilot — max-width em monitores ultra-wide

- **Status**: Done (2026-05-31 — max-width page 1200px, thread 42rem, PR com T-326 backlog)
- **Priority**: 🔵 Medium
- **Owner**: Cursor / AI Radar
- **Epic**: Fleet Copilot / reports.dnor.io / web-v2
- **Est**: 2h
- **Depends on**: T-323 (UI Fleet Copilot live)
- **Blocks**: Nenhum

## Context

Em monitores **extra-wide** (ultrawide, 34"+, >2560px), a view `#fleet-copilot` estica o layout horizontalmente: sidebar + thread + composer ocupam quase toda a largura da tela. Linhas de texto longas e distância olho↔conteúdo pioram a leitura (“virar a cabeça”).

O **DNOR shell** já limita a nav em `max-width: 1400px` (`.dnor-shell__inner`), mas a **área principal** do Copilot não herda um container equivalente — `.fleet-copilot-layout` usa grid full-bleed dentro de `.shell`.

**Objetivo:** coluna de leitura confortável (~65–75ch no thread), layout centralizado, sem perder densidade útil em laptops.

Arquivos:

- `apps/rs-observability-api/web-v2/src/index.css` — `.fleet-copilot-*`
- `apps/rs-observability-api/web-v2/src/components/FleetCopilotPage.tsx`
- Referência: `.dnor-shell__inner` (1400px)

---

## T-325a — Container max-width + centering

- **Est**: 45min

### Checklist

- [x] `.fleet-copilot-page`: `max-width: 1200px` + `margin-inline: auto` + `width: 100%`
- [x] `.fleet-copilot-layout`: grid sidebar + chat dentro do page cap
- [x] Hero + banner dentro de `.fleet-copilot-page`
- [x] Locked card `max-width: 36rem` centralizado

### Valores sugeridos (ajustar no PR)

| Token | Valor | Notas |
|-------|-------|-------|
| `--fleet-copilot-page-max` | `1200px` | alinhado ao shell 1400px, um pouco mais estreito para chat |
| `--fleet-copilot-thread-max` | `72ch` | largura ideal de prosa |
| Breakpoint “ultra-wide” | `min-width: 1600px` | só aplica cap se viewport >1600px (opcional) |

---

## T-325b — Thread / bubbles / composer

- **Est**: 45min

### Checklist

- [x] `.fleet-copilot-thread`: `align-items: center`, bubbles `max-width: 42rem`
- [x] Bubbles user `36rem`, assistant `42rem`
- [x] Composer dentro de `.fleet-copilot-chat` (grid column)
- [x] Source pills: `flex-wrap` existente

---

## T-325c — Validação visual

- **Est**: 30min

### Checklist

- [ ] 1920×1080 — layout atual aceitável (sem regressão)
- [ ] 3440×1440 ultrawide — conteúdo centralizado, ~1200px úteis
- [ ] Mobile `<900px` — stack vertical existente intacto
- [ ] Screenshot antes/depois anexado na task ou PR

---

## Critérios de aceite

- [x] Em viewport ≥1600px, coluna principal do Copilot **não** ultrapassa ~1200px de largura útil
- [x] Texto do assistant legível sem scan horizontal excessivo
- [x] Nav DNOR (1400px) e Copilot (1200px) — coluna mental coerente
- [x] Mobile `<900px` stack intacto

## Fora de escopo (follow-up opcional)

- Aplicar o mesmo padrão a **Overview / Nodes / Intel** (epic T-301 shell) — task separada se necessário
- `container-type` / container queries avançadas

## Referências

- [T-323](T-323-Fleet-Copilot-UI-Reports.md)
- [T-301](T-301-Node-Fleet-v2-UI-mockup-DNOR-period-export-done.md) — DNOR shell
- `web-v2/src/index.css` — `.dnor-shell__inner { max-width: 1400px }`
