# T-323: Fleet Copilot — UI no reports.dnor.io (web-v2)

- **Status**: Done (MVP 2026-05-31 — #fleet-copilot, presets, SSE tokens, PR #367)
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: Fleet Copilot / Node Fleet / reports.dnor.io
- **Est**: 2d (323a–323d)
- **Depends on**: T-322 (API `/api/fleet/chat` + auth)
- **Blocks**: Nenhum (último epic MVP)

## Context

Interface operador no **Cluster Pulse** (`apps/rs-observability-api/web-v2`) para fazer perguntas read-only sobre `ssdnodes-monstro` e fleet OCI, consumindo apenas APIs same-origin autenticadas.

**Princípios UX + segurança:**

- Presets seguros (sem prompt livre perigoso como default)
- Banner permanente: **read-only, sem remediação**
- Citação de fontes (`/ops/host/disk`, etc.)
- **Nunca** embedar tokens no bundle Vite
- Login via URL com key (operador) ou redirect — cookie HttpOnly

Arquivos relevantes:

- `web-v2/src/components/NodesPanel.tsx` — Node Fleet
- `web-v2/src/context/DnorShellContext.tsx` — views hash
- `web-v2/src/hooks/useLiveOverview.ts` — padrão fetch

---

## T-323a — Fluxo de login + gate de UI

- **Est**: 4h

### Checklist

- [ ] Rota/hash `/#fleet-copilot` ou query `?fleet-login=1`
- [ ] Documentar URL operador: `https://reports.dnor.io/fleet-copilot?key=<from-secret>`
- [ ] Hook `useFleetCopilotSession`:
  - [ ] `GET /api/fleet/copilot/session` (novo endpoint leve — retorna `{ authenticated: bool }` sem dados sensíveis)
  - [ ] Se não autenticado → empty state com instrução (sem expor que key existe)
- [ ] Após login bem-sucedido, redirect para `/#nodes` com drawer aberto
- [ ] Logout: `POST /api/fleet/copilot/logout` clear cookie

### Estados UI

| Estado | UI |
|--------|-----|
| Feature disabled (`404` em session) | Componente oculto (zero mention) |
| Não autenticado | Card “Sessão necessária” + link doc interno |
| Autenticado | Chat drawer habilitado |

### DoD

- Sem key → chat invisível ou locked
- Com key via URL → cookie + chat unlocked

---

## T-323b — FleetChatPanel + presets

- **Est**: 1d

### Layout

- [ ] Drawer/coluna direita em `NodesPanel.tsx` (desktop) ou sheet (mobile)
- [ ] Header: **Fleet Copilot · Read-only**
- [ ] Preset chips (click = envia template):
  - [ ] “💾 Disco & memória SSDNodes” → `preset: ssdnodes-health`
  - [ ] “☸️ Pods & ingress” → `ssdnodes-k8s`
  - [ ] “🔐 SSH últimas 24h” → `ssdnodes-ssh`
- [ ] Input texto livre **secundário** (placeholder: “Pergunta sobre os dados coletados…”)
- [ ] Botão Send desabilitado durante request
- [ ] Histórico **só sessionStorage** (max 20 msgs) — não persistir server-side conteúdo completo

### Componentes

| Arquivo | Ação |
|---------|------|
| `web-v2/src/components/FleetChatPanel.tsx` | Novo |
| `web-v2/src/hooks/useFleetChat.ts` | POST /api/fleet/chat |
| `web-v2/src/types/fleetCopilot.ts` | Tipos |

### Acessibilidade

- [ ] `aria-live="polite"` na área de resposta
- [ ] Focus trap no drawer mobile

### DoD

- Presets funcionam end-to-end
- Mobile usable

---

## T-323c — Streaming SSE (se T-322f entregue)

- **Est**: 4h

### Checklist

- [ ] `useFleetChatStream` — `fetch` + `ReadableStream` parser SSE
- [ ] Typing indicator enquanto chunks chegam
- [ ] AbortController on unmount / new message
- [ ] Fallback para JSON non-stream se `stream: false`

### DoD

- Resposta longa renderiza incrementalmente
- Cancel não deixa orphan no servidor (best-effort)

---

## T-323d — Copy, disclaimers, source citations

- **Est**: 1h

### Checklist

- [ ] Banner fixo amarelo:
  > Assistente read-only. Não executa remediação. Verifique fontes antes de agir.
- [ ] Cada resposta lista `sources[]` da API como pills clicáveis (expand JSON raw opcional)
- [ ] Timestamp `collected_at` visível
- [ ] Link “Como funciona” → anchor doc (README Fleet Copilot)
- [ ] **Não** mostrar modelo/thinking chain interno

### DoD

- Operador vê de onde vieram os dados
- Disclaimer sempre visível com chat aberto

---

## CSP e frontend security

| Tópico | Decisão |
|--------|---------|
| CSP | Manter ausente **ou** adicionar `connect-src 'self'` apenas — **nunca** domínio Ollama |
| Tokens | Zero no `import.meta.env` production |
| XSS | Escapar `reply` markdown — usar text content ou sanitizer mínimo (sem `dangerouslySetInnerHTML` raw) |
| CORS | Same-origin only |

---

## Testes

### Manual QA checklist

- [ ] Login key inválida → 404, UI locked
- [ ] Preset health → resposta menciona disco real
- [ ] Rate limit → toast “Aguarde X segundos”
- [ ] Feature off → componente ausente
- [ ] Ultrawide + mobile (padrão T-137/T-139)

### Automatizado (opcional)

- [ ] Playwright/smoke: preset click mock API (se harness existir)

---

## Critérios de aceite (epic T-323)

- [x] Chat visível em `https://reports.dnor.io/#fleet-copilot` após login (+ teaser em `#nodes`)
- [x] Presets cobrem casos ops principais (health, k8s, ssh)
- [x] Disclaimer + sources em toda resposta
- [x] Zero secrets no bundle
- [x] Coerente visualmente com DNOR shell (T-301)

## Evidência live (preencher na execução)

- [x] UI em `https://reports.dnor.io/#fleet-copilot` (nav Copilot + presets + SSE)
- [x] Harness: `bash scripts/harness/validate_fleet_copilot.sh` (8/8)
- [x] Login: `curl -c cj "https://reports.dnor.io/fleet-copilot?key=$KEY"` → 302 + cookie
- [x] SSE: `POST /api/fleet/chat/stream` → `event: phase` + `event: token` + `event: done`
- [x] Gateway ollama: fallback stream + resposta pt-BR (deploy monstro 2026-05-31)
- [x] Imagem OCI: `rs-observability-api:1780227427`+ (UI sessão/locked fix)

## Referências visuais

- `web-v2/src/components/NodesPanel.tsx`
- `web-v2/src/components/FleetOverviewTable.tsx`
- Mockup DNOR shell (T-301)
