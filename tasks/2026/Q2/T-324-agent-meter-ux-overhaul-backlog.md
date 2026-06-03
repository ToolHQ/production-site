# T-324 — agent-meter UX/UI Overhaul (Backlog Mestre)

> **Epic**: SaaS Revenue → Polish & Conversion
> **Owner**: Copilot/VSCode
> **Estimativa total**: ~10 dias (subdividido em T-324.1 → T-324.16)
> **Auditoria**: 2026-06-03 navegando https://agent-meter.dnor.io (Chrome DevTools MCP)
> **Páginas inspecionadas**: `/`, `/pricing`, `/login`, `/cost`, `/alerts`, `/conversations/:id/timeline`, `/tasks`, `/reports`

---

## 🚨 Achados críticos da auditoria

| # | Página | Severidade | Achado |
|---|--------|:----------:|--------|
| 1 | **Global** | 🔴 P0 | Glyphs emoji do nav (`💰 Cost`, `🔔 Alerts`, `💎 Pricing`, `👤 Sign in`) renderizam como □ quadrados em vários browsers (font sem cobertura emoji). Preciso de **icon set SVG** (Lucide/Tabler/Heroicons) inline. |
| 2 | **Global** | 🔴 P0 | Não há **design system** — cada página tem CSS inline próprio, paleta divergente, espaçamentos arbitrários. Tokens (cor/espaçamento/tipografia/raio/sombra) ausentes. |
| 3 | **Global** | 🔴 P0 | Não há **layout shell**: cada rota é HTML standalone com header copiado. Falta sidebar fixa, breadcrumbs, user menu, search global. |
| 4 | **Global** | 🟠 P1 | Não há **footer** em nenhuma página (status, legal, docs, GitHub, version). |
| 5 | **Global** | 🟠 P1 | **Logotipo agent-meter ausente** — header tem só texto "agent-meter". |
| 6 | **Global** | 🟠 P1 | **Favicon ausente** ou genérico. |
| 7 | **Global** | 🟠 P1 | Sem **meta tags** OG/Twitter para sharing (cards quebrados em LinkedIn/X). |
| 8 | **Global** | 🟡 P2 | Sem **modo claro/escuro toggle** — só dark hardcoded (alguns mercados B2B preferem light). |
| 9 | **Global** | 🟡 P2 | Sem responsividade mobile real — tabelas estouram, sidebar nem existe. |
| 10 | **`/`** | 🔴 P0 | Painel "Send Test Event" exposto em prod no dashboard — é dev-only. Mover para `/dev/test` ou hide atrás de `?dev=1`. |
| 11 | **`/`** | 🟠 P1 | Header com 5 botões "💰 Cost / 🔔 Alerts / 💎 Pricing / 👤 Sign in / Healthy" — cluttered, mistura nav com status. Mover Healthy para badge separado. |
| 12 | **`/`** | 🟠 P1 | Filtros 1h/6h/24h/7d/30d sem **date range picker** custom (precisa para enterprise). |
| 13 | **`/`** | 🟠 P1 | Chart "Calls Over Time" anêmico — sem eixos visíveis, sem grid, sem tooltip rico, só uma linha. |
| 14 | **`/`** | 🟠 P1 | Tabelas "Top Tools" / "Top MCP Servers" / "Recent Errors" sem **sparklines** ou bar mini-charts inline. |
| 15 | **`/`** | 🟡 P2 | Cards KPI (Total Events / Total Cost / etc) sem **delta vs período anterior** (ex: ↑12% vs 7d atrás). |
| 16 | **`/`** | 🟡 P2 | Empty state "0 MCP Servers" sem CTA — deveria sugerir setup. |
| 17 | **`/pricing`** | 🟠 P1 | Sem **logos de clientes** ("Used by..."). |
| 18 | **`/pricing`** | 🟠 P1 | Sem **tabela comparativa** completa Free vs Pro vs Team vs Enterprise (features lado-a-lado). |
| 19 | **`/pricing`** | 🟠 P1 | Sem **screenshot/mockup do produto** no hero — pricing pages B2B convertem 30%+ com hero visual. |
| 20 | **`/pricing`** | 🟠 P1 | Sem **toggle Mensal/Anual** (Annual com desconto = lever de conversão). |
| 21 | **`/pricing`** | 🟠 P1 | Headline quebrada ugly: "Stop guessing what your" / "agents cost." — precisa controle tipográfico. |
| 22 | **`/pricing`** | 🟠 P1 | Sem **testimonials/quotes** de developers. |
| 23 | **`/pricing`** | 🟠 P1 | Sem **CTA secundário no fim** após FAQ ("Still have questions? Talk to us"). |
| 24 | **`/pricing`** | 🟡 P2 | Sem **calculadora de ROI** (input: tokens/mês, output: spend & insight). |
| 25 | **`/login`** | 🟠 P1 | Página minimalista demais — sem **value prop lateral** (split-screen com benefits). |
| 26 | **`/login`** | 🟠 P1 | Só GitHub OAuth — sem opção magic link / email-password / Google. |
| 27 | **`/login`** | 🟡 P2 | Sem **terms/privacy links** abaixo do botão. |
| 28 | **`/cost`** | 🟠 P1 | KPIs ok, mas **bar chart diário pequeno** e sem zoom. |
| 29 | **`/cost`** | 🟠 P1 | Tabela "Top Models by Cost" sem **share % visual** (bar overlay). |
| 30 | **`/cost`** | 🟠 P1 | Sem **breakdown por org/usuário/projeto** (multi-tenant ainda não exposto na UI). |
| 31 | **`/cost`** | 🟠 P1 | Sem **forecast/projection** (linear extrapolation até fim do mês). |
| 32 | **`/cost`** | 🟡 P2 | Pricing reference table sem search/filter, sem destaque do modelo mais usado pelo usuário. |
| 33 | **`/alerts`** | 🟠 P1 | Form-heavy — falta **galeria de templates** ("Daily $5 budget", "Error rate >5%", "p95 >2s") com 1-click apply. |
| 34 | **`/alerts`** | 🟠 P1 | Sem **canais de notificação** (Slack/Email/Webhook UI) — só rule + history. |
| 35 | **`/alerts`** | 🟠 P1 | Histórico de alerts sem **severity icons** coloridos / status (acknowledged/resolved). |
| 36 | **`/alerts`** | 🟡 P2 | Sem **mute/snooze** UI. |
| 37 | **`/timeline`** | 🟠 P1 | Mini-mapa de densidade muito **pequeno** (16px height) — difícil arrastar. |
| 38 | **`/timeline`** | 🟠 P1 | Legenda (llm/tool/fs/shell/error) cluttered no topo — mover para drawer ou rodapé. |
| 39 | **`/timeline`** | 🟠 P1 | Drawer de evento sem **prompt/response preview** (só metadata). |
| 40 | **`/timeline`** | 🟡 P2 | Sem **share link público** read-only para discussão. |
| 41 | **`/tasks`** | 🔴 P0 | **Retorna JSON cru no browser** — sem UI! Precisa página `/tasks` HTML lista. |
| 42 | **`/reports`** | 🟠 P1 | **404** — rota não existe; ou esconder do nav ou criar hub de reports. |
| 43 | **404** | 🟡 P2 | Página de erro do Chrome default — precisa **404 customizado** com link voltar. |

---

## 📦 Sub-tasks (executáveis)

### 🎨 Foundation (T-324.1 → T-324.4)

#### **T-324.1 — Design System v1: tokens + componentes base** _(2d, 🚨 Critical)_
- `crates/collector/ui/_design/tokens.css`: cores (`--am-bg`, `--am-surface`, `--am-border`, `--am-text-*`, `--am-accent-*`, `--am-success/warn/danger`), espaçamentos (4/8/12/16/24/32/48), tipografia (font-stack Inter, sizes 11/12/14/16/18/24/32, weights 400/500/600/700), raios (4/6/8/12), sombras (sm/md/lg).
- `_design/components.css`: `.am-btn` (primary/secondary/ghost/danger), `.am-input`, `.am-select`, `.am-card`, `.am-table`, `.am-badge` (success/warn/danger/info/neutral), `.am-kpi`, `.am-tab`, `.am-tooltip`, `.am-modal`, `.am-toast`.
- `_design/icons.svg`: sprite SVG com 30+ ícones Lucide-style (cost, alert, pricing, user, github, chart, search, settings, logout, copy, external, chevron, check, x, info, warning, plus, filter, calendar, clock, server, tool, model, error, sparkles).
- Deprecar todo CSS inline duplicado entre páginas — mover para shared.

#### **T-324.2 — Layout shell global (sidebar + topbar + breadcrumbs)** _(1.5d, 🚨 Critical)_
- `ui/_partials/shell.html` (server-side included via simples template fn em Rust ou string concat) com:
  - **Sidebar** 220px: logo + nav items (Dashboard, Conversations, Cost, Alerts, Reports, Settings) + collapse to 56px.
  - **Topbar**: breadcrumbs + global search (Cmd+K) + notifications + user menu (avatar via `/api/me`).
  - **Footer global**: "agent-meter v0.1 · Status · Docs · GitHub · Privacy · Terms".
- Aplicar shell em todas as 7 páginas existentes.

#### **T-324.3 — Brand: logo + favicon + meta tags + OG cards** _(0.5d, 🔼 High)_
- Logo SVG simples (geometric meter glyph + word "agent-meter").
- Favicon set (`favicon.ico`, `favicon-32.png`, `apple-touch-icon.png`, `safari-pinned-tab.svg`).
- `<meta name="description">`, `og:title`, `og:image` (1200×630 pricing OG card), `twitter:card=summary_large_image`.
- `manifest.webmanifest` + theme-color.

#### **T-324.4 — Light mode toggle + system preference** _(0.5d, 🔵 Medium)_
- CSS dual: `[data-theme="dark"]` e `[data-theme="light"]`.
- Toggle no user menu, persiste em localStorage, default = `prefers-color-scheme`.

---

### 🏠 Dashboard (T-324.5 → T-324.7)

#### **T-324.5 — Dashboard refactor: KPI cards + sparklines + deltas** _(1d, 🔼 High)_
- 4 KPI cards top-row: Total Events, Total Cost, Avg Latency p95, Error Rate.
  - Cada um com: valor grande, delta vs período anterior (↑/↓ %), sparkline 30-pt SVG inline.
- Date range picker custom (presets + calendar).
- Esconder painel "Send Test Event" atrás de `?dev=1` (ou mover p/ `/dev`).
- Mover badge "Healthy" do header para **status bar do footer** (sempre visível).

#### **T-324.6 — Charts upgrade: chart "Calls Over Time" rico** _(0.5d, 🔼 High)_
- SVG chart com: grid sutil, eixos legendados, tooltip hover (data + value + delta), área gradient.
- Multi-series: events, cost (overlay opcional).
- Sem libs (manter zero-deps, SVG puro).

#### **T-324.7 — Tabelas "Top Tools/Models/Servers" com bar inline** _(0.5d, 🔼 High)_
- Cada row: nome, count, **bar share %** colorida proporcional, mini-sparkline.
- Sort por coluna, search, paginação se >10.

---

### 💎 Pricing & Marketing (T-324.8 → T-324.10)

#### **T-324.8 — Pricing: tabela comparativa + Mensal/Anual + ROI calc** _(1d, 🚨 Critical)_
- Toggle Mensal/Anual (Annual −20%).
- Tabela completa **features × tier** abaixo dos cards (Events/mo, Retention, Seats, Alerts, Webhooks, SSO, SLA, Support).
- Calculadora ROI: input tokens/mês → output "you'd save $X/month on bad models".
- Logos placeholder ("As seen on...", "Used by...") com 4-6 brand SVGs (use Hacker News / Product Hunt / GitHub badges reais).

#### **T-324.9 — Pricing: hero visual + testimonials + bottom CTA** _(0.5d, 🔼 High)_
- Hero: split layout — texto à esquerda, screenshot do dashboard com waterfall à direita.
- Headline em 1 linha responsiva (control via clamp tipográfico).
- Section de testimonials (3 cards com foto+nome+role+quote — mock até real).
- CTA bottom pós-FAQ: "Still have questions? Email founders@agent-meter.com" + Discord/Slack.

#### **T-324.10 — Login page split-screen + value prop** _(0.5d, 🔵 Medium)_
- Layout 50/50: form à direita, value prop à esquerda (3 bullet benefits + screenshot).
- Footer "By signing in, you agree to Terms & Privacy" com links.
- Preparar slot para Magic Link e Google (UI desabilitado com tooltip "Coming soon").

---

### 💰 Cost & Alerts (T-324.11 → T-324.13)

#### **T-324.11 — Cost page: org/user breakdown + forecast + share %** _(1d, 🔼 High)_
- Breakdown tabs: by Model | by User | by Project | by Tool.
- Forecast linha tracejada até fim do mês (linear regression).
- "Top Models by Cost": adicionar bar share % overlay.
- Pricing reference table: search, badge "your most-used".

#### **T-324.12 — Alerts: rule template gallery + severity UI** _(0.5d, 🔼 High)_
- 6 cards de templates ("Daily $5 budget", "Error rate >5% (5min)", "Latency p95 >2s", "Token spike 3× rolling avg", "Hard cap $100/mo", "New model detected") com botão "Use template".
- Histórico: severity icon colorido (🔴/🟠/🟡), status badge (firing/acknowledged/resolved), botão Mute/Resolve.

#### **T-324.13 — Notification channels UI** _(1d, 🔼 High)_
- Settings panel: Slack webhook, Email recipients, generic Webhook URL, PagerDuty key.
- Test send button per channel.
- Migration nova: `alert_channels (id, org_id, type, config jsonb, created_at)`.
- API: `GET/POST/DELETE /api/alerts/channels`.

---

### 🎬 Timeline & Detail Pages (T-324.14 → T-324.15)

#### **T-324.14 — Timeline: minimap larger + drawer rich + share link** _(1d, 🔼 High)_
- Minimap 40px height + zoom controls (+/− buttons além de ctrl+wheel).
- Drawer: tabs (Overview / Prompt / Response / Headers / Raw JSON), copy buttons.
- Botão "Share read-only link" → gera token público sem auth (rota `/share/timeline/:token`).

#### **T-324.15 — `/tasks` HTML page + 404 customizado** _(0.5d, 🔵 Medium)_
- `/tasks`: tabela HTML (id, ide, repo, branch, started/ended, duration, skill).
- Página 404 styled com search box + link home.
- Esconder ou implementar `/reports` (decidir em design review).

---

### ♿ Acessibilidade & Performance (T-324.16)

#### **T-324.16 — A11y + Lighthouse pass** _(1d, 🔵 Medium)_
- Contraste WCAG AA em todos os tokens.
- Focus rings visíveis em todos interactive.
- ARIA labels em ícones-only buttons.
- `prefers-reduced-motion`.
- Lighthouse target: Performance ≥90, A11y ≥95, Best Practices ≥95, SEO ≥95.
- Bundle: nenhum JS lib externo; todo CSS inline ≤30KB gzip por página.

---

## 📊 Resumo de prioridade

| Prioridade | Tasks | Estimativa |
|:----------:|:-----:|:----------:|
| 🚨 Critical | T-324.1, T-324.2, T-324.8 | 4.5d |
| 🔼 High | T-324.3, T-324.5, T-324.6, T-324.7, T-324.9, T-324.11, T-324.12, T-324.13, T-324.14 | 6d |
| 🔵 Medium | T-324.4, T-324.10, T-324.15, T-324.16 | 2.5d |

**Total**: ~13 dias. Quick wins primeiros 2 dias: T-324.1 + T-324.3 + T-324.5 desbloqueiam visual completo de prod.

---

## 🎯 Definition of Done (do épico)

- [ ] Design system tokens documentado em `ui/_design/README.md`.
- [ ] Todas as 7 páginas usam shell global + ícones SVG (zero emoji broken).
- [ ] `/pricing` tem hero visual + comparison table + Mensal/Anual + ROI calc.
- [ ] `/` dashboard tem KPI deltas + sparklines + chart rico.
- [ ] Mobile breakpoint funcional em ≥768px (sidebar collapse).
- [ ] Lighthouse ≥90/95/95/95 nas 3 páginas-chave (`/`, `/pricing`, `/login`).
- [ ] OG cards renderizam corretamente (testar em LinkedIn validator + Twitter card validator).
- [ ] Browser MCP smoke: console limpo + screenshots de todas as páginas em `tmp/audit/`.
