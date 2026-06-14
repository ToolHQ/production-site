# T-340 — Checklist de validação visual (agente + operador)

**Owner:** Cursor / AI Radar + sign-off **Reinaldinho**  
**URL base:** https://reports.dnor.io  
**Imagem alvo:** `rs-observability-api:1780577696` (ou tag atual no harness)  
**Última automação:** preencher após rodar `scripts/harness/validate_t340_visual.sh`

---

## Como usar

| Coluna | Quem |
|--------|------|
| **Auto** | Agente: CLI, curl, harness, MCP browser (CDP/screenshot) |
| **Humano** | Só você: “faz sentido operacional?”, densidade no ultrawide, triage real 30 min |

Legenda: `✅` pass · `❌` fail · `⏭` skip · `—` pendente

---

## 0 — Pré-voo (CLI, ~2 min)

| # | Check | Comando / critério | Auto | Humano |
|---|--------|-------------------|------|--------|
| 0.1 | Health API | `curl -fsS https://reports.dnor.io/health` → `ok` | — | — |
| 0.2 | Live overview | `curl -fsS .../api/live/overview` → `available:true`, `stale:false` | — | — |
| 0.3 | Imagem cluster | `kubectl get deploy rs-observability-api-deployment -o jsonpath='{.spec...image}'` | — | — |
| 0.4 | Harness Fleet | `./scripts/harness/validate_fleet_copilot.sh` → **30/30** | — | — |
| 0.5 | Bundle T-340 | JS sem placeholder; CSS `dnor-overview-nav`, `storage-row--pressure`, `dnor-catalog-cta` | — | — |

---

## 1 — As 7 views (hash routing)

| View | URL | Auto (MCP) | Humano |
|------|-----|------------|--------|
| Overview | `/` | Screenshot light+dark; presença `#signal-grid`, `.dnor-overview-nav`, `.dnor-platform-fold`; sem texto placeholder | KPIs above fold 1080p; TOC útil |
| Nodes | `/#nodes` | Screenshot; `.fleet-cluster-header`, `.nodes-panel`; tabela ou cards mobile | Toggle honeypot; tooltips |
| Incidents | `/#incidents` | Screenshot; `.priority-grid`; copy PT nos títulos | Priorização faz sentido |
| Reports | `/#reports` | Screenshot; `#dnor-catalog`; sem `Routes: /api/` no DOM | Catálogo legível |
| Intel | `/#intel` | Screenshot; painéis Coroot | Valor vs overview |
| Settings | `/#settings` | Screenshot; `.dnor-settings` | Thresholds / deep links |
| Fleet Copilot | `/#fleet-copilot` | Login via key env; screenshot; SSE smoke já no harness | Quota, presets, thread |

---

## 2 — Dark mode (prioridade — feedback: “feio”)

| # | Check | Auto | Humano |
|---|--------|------|--------|
| D.1 | `html` ou `body` tem classe `dark` após toggle | CDP: `document.documentElement.classList` | — |
| D.2 | Fundo não “vaza” claro (body gradient dark) | Screenshot + `getComputedStyle(body).background` | Harmonia geral |
| D.3 | Tabelas fleet/nodes: texto legível, bordas não gritantes | Screenshot `/#nodes` dark | — |
| D.4 | Pills / panel-tags contraste WCAG ~4.5:1 | CDP contrast ratio amostra (pill, section-title) | — |
| D.5 | Command card + signal-mini fundo coerente | Screenshot overview dark | — |
| D.6 | Storage pressure row visível (não sumir no dark) | `.storage-row--pressure` no DOM + screenshot | — |
| D.7 | Copilot: composer + bubbles legíveis | Screenshot `/#fleet-copilot` dark | — |
| D.8 | Sem “faixas brancas” em `.panel`, `.catalog-side`, `.table-shell` | CDP background-color em 5 seletores | — |

**Gate dark:** ≥ 6/8 Auto ✅ antes de pedir sign-off humano só no gosto fino.

---

## 3 — Responsivo (MCP viewport)

| # | Viewport | View | Auto |
|---|----------|------|------|
| R.1 | 390×844 | Overview, Nodes, Copilot | Screenshot; nav não quebra crítico |
| R.2 | 1280×720 | Overview | TOC + masthead compact |
| R.3 | 1920×1080 | Overview | KPIs visíveis sem scroll (estimativa scrollY &lt; 120) |
| R.4 | 2560×1440 | Copilot | Coluna copilot ≤ ~920px (T-325) |

---

## 4 — Copy PT-BR (humano confirmou OK — regressão só)

| # | Check | Auto |
|---|--------|------|
| C.1 | Bundle sem `IMMEDIATE ACTION`, `Next action`, `Waiting for node` | `grep` no `app.js` servido |
| C.2 | IncidentList: Crítico/Alerta | grep bundle |
| C.3 | Fleet table: colunas PT (Nó, Ambiente, …) | grep ou snapshot |

---

## 5 — Sessão operador (30 min triage real) — só humano

- [ ] Abrir overview com incidente real (ou simular stale) e seguir “Próxima ação”
- [ ] Filtrar nó por cluster; export CSV se usar
- [ ] Perguntar Copilot: preset SSDNodes + nó OCI; validar fast path vs Gemma
- [ ] Alternar dark/light durante triage — dark aceitável após fixes D.*
- [ ] Anotar 3 fricções máx. → viram cards T-340-D

**Sign-off:** _______________ Data: __________

---

## Scripts

```bash
# Automático (agente)
./scripts/harness/validate_fleet_copilot.sh
./scripts/harness/validate_t340_visual.sh   # curl + bundle grep + opcional MCP

# Login Copilot (se secret local)
export FLEET_COPILOT_LOGIN_KEY="$(kubectl get secret fleet-copilot-creds -n default -o jsonpath='{.data.FLEET_COPILOT_LOGIN_KEY}' | base64 -d)"
curl -sS -c /tmp/rc.jar "https://reports.dnor.io/fleet-copilot?key=$FLEET_COPILOT_LOGIN_KEY"
```

---

## Registro de execução

| Data | Agente | Auto pass | Humano | Notas |
|------|--------|-----------|--------|-------|
| 2026-06-04 | Cursor | CLI `validate_t340_visual.sh` **15/15**; `validate_fleet_copilot.sh` **30/30**; MCP nodes dark 390px screenshot | Pendente sign-off 30 min | Dark mode feio → patch local `index.css`+`app.css` **ainda não deployado**; copy PT-BR OK |

### Evidências MCP (agente)

| Arquivo | View |
|---------|------|
| `tasks/audit-ui/validate-nodes-dark-390.png` | `#nodes`, dark, 390×844 |
| `tasks/audit-ui/validate-overview-dark.png` | `/` overview, dark |
