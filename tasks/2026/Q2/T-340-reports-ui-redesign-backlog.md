# T-340 — Reports.dnor.io — Backlog extenso de UI/UX (audit 2026-06-03)

**Owner:** Cursor / AI Radar  
**Prioridade epic:** 🔼 High  
**Estimativa total:** 3–5 semanas (fases)  
**URL auditada:** https://reports.dnor.io  
**Evidências:** `tasks/audit-ui/*.png` (overview, nodes, incidents, reports, intel, settings, copilot, dark, mobile)

## Resumo executivo

O console já tem base sólida (design tokens, dark mode, multi-view, Fleet Copilot, dados live). O gap para **produto premium** está em: **polimento**, **densidade operacional**, **consistência PT-BR**, **mobile**, **hierarquia** e **remoção de copy técnica/placeholder**. Várias fricções foram reproduzidas no browser (nav truncada, tema duplicado, hero alto, página kilometrica no Overview).

---

## Mapa de superfícies

| View | Hash | Estado no audit |
|------|------|----------------|
| Overview | `/` | Masthead + 15+ seções empilhadas |
| Nodes | `#nodes` | Fleet table + período 24h/7d |
| Incidents | `#incidents` | 2 painéis (Immediate + Restart) |
| Reports | `#reports` | Catalog + artifacts |
| Intel | `#intel` | Só rail Coroot (repetido) |
| Settings | `#settings` | 3 cards mínimos |
| Fleet Copilot | `#fleet-copilot` | Layout dedicado; skeleton no load |

---

## P0 — Quebra percepção de produto (quick wins, 1–3 dias)

| ID | Item | Detalhe observado | Aceite |
|----|------|-------------------|--------|
| T-340-01 | **Remover toggle de tema duplicado** | `ThemeToggle` no `DnorTopNav` **e** no `DashboardHeader.meta-row` | Um único controle global (nav ou Settings) |
| T-340-02 | **Substituir copy placeholder** | Incidents: *"This block should explain why an operator needs to care now"* (`app.tsx:294`) | Copy PT-BR operacional (ex.: priorizar restarts > N em 1h) |
| T-340-03 | **Corrigir truncamento na nav** | "Reports" → "Rep", "Copilot" → "Cop" em viewport ~1200px | Nav responsiva: menu overflow, ícones, ou nav compacta |
| T-340-04 | **Indicador Live/Offline** | Bolinha vermelha no primeiro paint mesmo com API live (`/api/live/overview` OK após ~8s) | Skeleton + transição verde; tooltip com último refresh |
| T-340-05 | **Hero Overview mais baixo** | Masthead ocupa ~40% do fold antes dos KPIs | KPIs (SignalCard) visíveis sem scroll em 1080p |
| T-340-06 | **Erro global visível** | `#error-box` no rodapé do `<main>` | Toast/banner sticky no topo quando live/snapshot falham |
| T-340-07 | **i18n PT-BR consistente** | Mix EN/PT: "IMMEDIATE ACTION", "Restart Debt", "usado" vs labels EN | Glossário único; kickers em PT ou EN (não misturado) |
| T-340-08 | **Remover jargão de rota na UI** | Catalog: `Routes: /api/live/overview, ...` | Mover para tooltip "?" ou docs; operador não precisa ver paths |

---

## P1 — Design system & hierarquia visual (1 semana)

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-10 | **Unificar tokens CSS** | `--ink` / `--text-main`, `--muted` / `--text-muted` duplicados | Um mapa de tokens + deprecar aliases |
| T-340-11 | **Component library doc** | 3000+ linhas em `index.css` monolítico | Extrair: shell, panel, pill, table, fleet-copilot |
| T-340-12 | **Pills / status bar** | meta-row com 6+ pills (snapshot, live, prom, coroot, countdown, export) | Agrupar em "Status strip" colapsável; prioridade visual: crítico > live > snapshot |
| T-340-13 | **Badge semântico** | WARNING laranja igual para 1 ou 5 restarts | Escala: info / warn / critical; número no badge |
| T-340-14 | **Tipografia tabular** | Métricas, IPs, % disco | `font-variant-numeric: tabular-nums` em tabelas e KPIs |
| T-340-15 | **Headline serif vs UI sans** | Título editorial grande no hero | Manter serif só no marketing hero; views internas sans semibold |
| T-340-16 | **Contraste WCAG dark** | Muitos overrides manuais `:root.dark .pill` | Audit Lighthouse a11y ≥ 90 em light+dark |
| T-340-17 | **Focus visible** | Botões nav sem ring consistente | `:focus-visible` em todos interativos |
| T-340-18 | **Avatar / identidade** | Círculo "D" sem função | Menu usuário: tema, logout copilot, link docs |

---

## P1 — Navegação & IA (information architecture)

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-20 | **Breadcrumbs ou page title** | `#incidents` não mostra H1 "Incidents" — só bloco interno | Toda view: `dnor-page-head` padronizado |
| T-340-21 | **Overview table of contents** | Scroll infinito (storage, cron, certs, ingress, workloads…) | Sticky sub-nav lateral ou anchor pills |
| T-340-22 | **Intel view vazia de valor** | Só repete Coroot panels do Overview | Intel = métricas + SLO trends + compare períodos |
| T-340-23 | **Settings incompleto** | Thresholds diz "configure in Nodes" | Mover `ThresholdSettings` para Settings ou deep-link |
| T-340-24 | **Período global** | `period` só em `#nodes` | Opcional: período no shell afeta charts Overview |
| T-340-25 | **Deep links estáveis** | Hash routing OK | Compartilhar URL preserva scroll section (`#dnor-nodes`) |
| T-340-26 | **⌘K discoverability** | Search só mostra hint no desktop | Onboarding tooltip primeira visita |
| T-340-27 | **Copilot na nav vs produto** | Botão truncado; sem badge "Pro" / quota | Nav item com sublabel ou ícone + tooltip quota |

---

## P1 — Nodes / Node Fleet (T-301 follow-up)

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-30 | **Densidade tabela fleet** | Muitas colunas; scroll horizontal mobile | Colunas prioritárias + expand row |
| T-340-31 | **Cluster headers** | Agrupamento OCI/Hetzner/AWS (T-298) | Sticky group headers no scroll |
| T-340-32 | **Tooltip hover cards** | Sparklines no portal — bom, mas pesado mobile | Tap-to-pin no touch; dismiss on scroll |
| T-340-33 | **Honeypot rows** | Visual distinto? | Legenda + filtro "incluir honeypot" |
| T-340-34 | **Fleet Copilot teaser** | Card na sidebar nodes | CTA alinhado ao preset "Visão geral" |
| T-340-35 | **Export CSV/JSON** | ExportMenu no header | Export também na view Nodes com filtros aplicados |
| T-340-36 | **Empty state nodes** | "Waiting for node data…" genérico | Ilustração + checklist (tunnel? RBAC?) |

---

## P1 — Overview operacional (data-dense)

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-40 | **SignalCard vs SignalGrid** | Dois blocos de contadores similares | Unificar ou hierarquia clara (hero KPI vs detalhe) |
| T-340-41 | **Longhorn 100%+ disco** | Volumes com "100% usado" sem alarme visual forte | Destaque crítico + link ação runbook |
| T-340-42 | **Storage panel grid** | Muitos cards repetitivos | Heatmap ou tabela sortable por % uso |
| T-340-43 | **CronJob / Cert / Ingress** | Seções full-width no overview | Accordion "Plataforma" colapsado por default |
| T-340-44 | **Coroot panels duplicados** | Overview rail + Intel view | Single source; Intel expande |
| T-340-45 | **Service grid + telemetry** | Duas seções grandes | Tab "Services" vs "Telemetry" |
| T-340-46 | **Catalog zone no Overview** | Reports no final — correto mas longe | Link "Ver catálogo completo" → `#reports` |

---

## P1 — Incidents & triage

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-50 | **Dedicated incidents layout** | View só mostra 2 painéis sem contexto cluster | Header + resumo SLO + filtros namespace |
| T-340-51 | **Restart hotspots** | Segundo painel — bom | Link para workload/pod |
| T-340-52 | **Ação sugerida** | Lista só nome do pod | Botão "kubectl logs" copy (read-only) ou link Coroot |
| T-340-53 | **Ack/dismiss** | Não existe | Snooze incident (localStorage) para operador |

---

## P1 — Reports & catalog

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-60 | **Catalog table UX** | Denso, técnico | Busca, filtro linguagem, sort |
| T-340-61 | **Artifact library** | Sidebar estreita | Preview markdown/HTML inline |
| T-340-62 | **Deploy context** | Pouco ligado ao live | Badge "snapshot age" vs live diff |

---

## P2 — Fleet Copilot (produto)

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-70 | **Skeleton full-page** | Load mostra blocos cinza grandes | Skeleton só na thread; hero estável |
| T-340-71 | **Nav overlap Copilot** | "Cop" truncado ao lado search | Layout copilot: nav item ícone-only |
| T-340-72 | **Locked state UX** | Card login longo | QR/link copy button + admin hint |
| T-340-73 | **Quota no header** | Quota só sidebar | Pill "8/10 req" na top bar |
| T-340-74 | **Model badge legível** | `structured` / `meta` | Legend: Instant / Gemma / Manifest |
| T-340-75 | **Ultrawide** | CSS `--dnor-copilot-column` | Validar 3440px sem dead space |
| T-340-76 | **Histórico persistido** | sessionStorage only | Postgres + UI thread list (monetização) |

---

## P2 — Responsivo & mobile

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-80 | **Nav mobile** | 7 itens + search não cabem | Bottom nav ou hamburger com drawer |
| T-340-81 | **Tables → cards** | Breakpoints 980/680/560 | Uma estratégia documentada por componente |
| T-340-82 | **Touch targets** | Pills e chips < 44px | min-height 44px em mobile |
| T-340-83 | **Copilot composer** | Input + chips hosts | Stack vertical; safe-area iOS |
| T-340-84 | **Horizontal scroll** | `overflow-x: auto` em tabelas | Indicador sombra "mais colunas →" |

---

## P2 — Performance & perceived speed

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-90 | **Lazy load por view** | Todos hooks rodam em toda view | Split data fetching por `view ===` |
| T-340-91 | **Skeleton por seção** | Blocos genéricos | Skeleton matching layout (table rows, cards) |
| T-340-92 | **Stale data badge** | `stale` no live pill | Banner amarelo global quando stale |
| T-340-93 | **Bundle size** | `app.js` monolítico | Code-split por route hash |
| T-340-94 | **Refresh countdown** | Pill "🔄 12s" | Configurável; pause quando tab hidden |

---

## P2 — Acessibilidade

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-A1 | **Status só cor** | Bolinha verde/vermelha | aria-live + texto "Live" |
| T-340-A2 | **Charts** | Cluster metrics — contraste | Padrões não só cor |
| T-340-A3 | **Reduced motion** | Animações progress bar | `prefers-reduced-motion` |
| T-340-A4 | **Screen reader nav** | Muitos `button` na nav | `aria-current="page"` |

---

## P3 — Premium / monetização / marca

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-M1 | **Landing produto** | Hero atual é interno | Página marketing + pricing tier |
| T-340-M2 | **White-label** | DNOR fixo | Logo/config por tenant |
| T-340-M3 | **PDF export branded** | Export menu básico | Relatório executivo PDF |
| T-340-M4 | **Notificações** | Sem push/email | Webhook alertas críticos |
| T-340-M5 | **Playwright visual regression** | T-328 smoke only | Percy/Chromatic nos 7 views |
| T-340-M6 | **Storybook** | Sem isolamento componentes | Storybook web-v2 |

---

## P3 — Conteúdo & confiança

| ID | Item | Detalhe | Aceite |
|----|------|---------|--------|
| T-340-C1 | **Runbook links** | Painéis sem "o que fazer" | Link para runbook em Longhorn/Cert/Incident |
| T-340-C2 | **Tooltips métricas** | CPU% sem contexto | Threshold legend |
| T-340-C3 | **Versão build** | Sem build id na UI | Footer: image tag + git sha |
| T-340-C4 | **Changelog in-app** | Deploys invisíveis | "O que mudou" modal pós-deploy |

---

## Fases sugeridas (execução)

### Fase A — Polish crítico (P0) — **2–3 dias**
T-340-01 … T-340-08

### Fase B — Shell & navegação (P1 nav + DS) — **1 semana**
T-340-10 … T-340-27

### Fase C — Superfícies de dados (Nodes + Overview) — **1–1.5 semanas**
T-340-30 … T-340-46

### Fase D — Copilot produto + mobile — **1 semana**
T-340-70 … T-340-84

### Fase E — Premium & growth (P3) — **backlog**
T-340-M*, T-340-C*

---

## Dependências técnicas

- `apps/rs-observability-api/web-v2/src/index.css` — refactor prioritário
- `app.tsx` — copy + lazy views
- `DnorTopNav.tsx` / `DashboardHeader.tsx` — shell
- `NodesPanel.tsx` — maior superfície
- Skill: `.agents/skills/ui-ux-excellence/SKILL.md`

---

## Critérios de "done" do epic T-340

1. Lighthouse Performance + Accessibility ≥ 85 (mobile + desktop)
2. Zero strings placeholder em produção
3. Nav legível 320px–4K sem truncar labels
4. Overview: KPIs above fold em 1080p
5. Harness visual smoke (Playwright) nas 7 views
6. Sign-off operador (você) em sessão de 30 min triage real

---

## Referência rápida — screenshots

| Arquivo | Conteúdo |
|---------|----------|
| `tasks/audit-ui/overview-light.png` | Primeiro paint offline |
| `tasks/audit-ui/overview-live-light.png` | Overview full scroll live |
| `tasks/audit-ui/overview-live-dark.png` | Dark mode |
| `tasks/audit-ui/nodes-light.png` | Nodes full page |
| `tasks/audit-ui/nodes-mobile-dark.png` | Mobile 390px |
| `tasks/audit-ui/incidents-light.png` | Incidents + placeholder copy |
| `tasks/audit-ui/reports-light.png` | Catalog zone |
| `tasks/audit-ui/intel-light.png` | Intel thin |
| `tasks/audit-ui/settings-light.png` | Settings skeleton |
| `tasks/audit-ui/copilot-light.png` | Copilot loading |
