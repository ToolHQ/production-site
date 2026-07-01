# Cursor Queue — AI Radar & cluster ops

> **Sincronizado**: 2026-06-10 · branch `feat/t-307-longhorn-headroom`

## Próximas 10 (ordem de execução)

| # | ID | Tarefa | Prioridade | Status |
| -: | :- | :----- | :--------- | :----- |
| 1 | **T-302** | qdbback TLS/Prometheus/AL2023 | 🔵 Medium | 🏎️ **próximo** |
| 2 | **T-347** | Deploy workers citools (E2E + secrets) | 🔼 High | 📋 |
| 3 | **T-362b** | Gmail OAuth + n8n credentials | 🚨 Critical | 📋 |

## Concluído neste sprint

| # | ID | Tarefa | Status |
| -: | :- | :----- | :----- |
| 1 | **T-311** | Hetzner BuildKit guardrails — PR #477 merged | ✅ |
| 2 | **T-307** | Longhorn headroom diag — harness PASS | ✅ |
| 2 | **T-362a** | Postgres email-intelligence K8s + RLS — harness PASS | ✅ |
| 2 | **T-362c** | Ollama bridge (socat + nginx proxy) — harness PASS | ✅ |
| 3 | **T-361** | n8n SSDNodes — live `n8n.ssdnodes.dnor.io` | ✅ |
| 2 | **T-362** | Email automation research/specs + subtasks T-362a…f | ✅ |
| 3 | **T-346** | citools deploy catalog + CLI | ✅ |
| 3 | **T-342** | Bump Sonar 26.6 + Jenkins 2.567 JDK25 | ✅ |
| 3 | **T-343** | Jenkins reverse proxy + security hardening | ✅ |
| 4 | **T-304** | MinIO backup headroom — 55% validado | ✅ |
| 5 | **T-305** | logrotate rsyslog — 4/4 nós OK | ✅ |
| 6 | **T-341** | SSDNodes Jenkins + SonarQube CE (PR #394) | ✅ |
| 7 | **T-345** | GitHub branch protection + Jenkins webhook | ✅ |
| 8 | **T-349** | Jenkins Blue Ocean + Stage View UX | ✅ |

## Epic citools Deploy (T-344)

Ver [CITOOLS-DEPLOY-BACKLOG.md](CITOOLS-DEPLOY-BACKLOG.md)

| Fase | ID | Status |
| :--- | :- | :----- |
| UX Jenkins | T-349 | ✅ |
| CI closure | T-345 | ✅ |
| Catálogo | T-346 | 📋 próximo após T-343 |
| Workers | T-347 | 📋 |
| Deploy job | T-348 | 📋 |

## Epic SSDNodes n8n (novo 2026-06-09)

| # | ID | Tarefa | Depende |
| -: | :- | :----- | :------ |
| 1 | **T-361** | n8n self-hosted Docker + TLS + auth | — |
| 2 | **T-362** | Email + Ollama — ADR, schema Postgres RLS, subtasks | T-361 |

## Em andamento (outros owners / paralelo)

| ID | Tarefa | Owner |
| :- | :----- | :---- |
| T-306 | OCI health watchdog | Cursor |
| T-302 | qdbback TLS/Prometheus | Cursor |
| T-324…T-329 | agent-meter UX/traces | Copilot |
| T-233 | VSCode OTLP doc | OpenCode |

## Epic agent-meter OSS (frente open-source rápida — novo 2026-06-30)

> **T-365** CI $0: Jenkins SSDNodes + webhook (`jenkins/agent-meter`). GHA aposentado.
> Plano: [AGENT-METER-OSS-PLAN.md](AGENT-METER-OSS-PLAN.md) · Destino: `dnorio/agent-meter`

| Fase | IDs | Tarefa | Status |
| :--- | :-- | :----- | :----- |
| A | AMOSS-1…5 | Extração de história (`filter-repo`) + scrub segredos/dnor.io + push | ✅ |
| B | AMOSS-6…11 | Binário standalone SQLite (sem SaaS), UI enxuta, "sobe e abre localhost" | ✅ |
| C | AMOSS-13/14/15 | CI + README/LICENSE OSS + `demo` seed nativo | ✅ |
| C | **AMOSS-12** | Release multiplataforma (binários) | ⏳ bloqueado (coordenar c/ frente Windows-proxy) |
| — | Polish 06-30 (PM) | README c/ screenshots reais + fix nav hardcoded, `calls_over_time`/`top_tasks` SQLite, `usd_cost` estimado no ingest, timeline tokens/custo | ✅ |

### Backlog OSS restante (Cursor / AI Radar)
| ID | Tarefa | Prioridade |
| :- | :----- | :--------- |
| AMOSS-12 | Release: tag `v0.1.0` + **T-365 Fase 3** Jenkins release job (sem GHA macos) | 🔼 High |
| AMOSS-16 | ✅ `install.sh`/`install.ps1` OSS — commit `e3ee14f` | 🔼 High |
| AMOSS-17 | ✅ Admin: DELETE conversation + POST reset | 🔵 Medium |
| AMOSS-18 | ✅ Burn-rate SQLite + Cost page sem refs SaaS | 🔵 Medium |
| AMOSS-19 | ✅ Clippy closures SQLite | 🟢 Low |

## Fase 23 — Fontes & trends (AI Radar)

| # | ID | Tarefa | Status |
| -: | :- | :----- | :----- |
| 1 | T-267…T-270 | RSS, vendors, watchlist, models | ✅ |
| 2 | **T-363** | Google Trends Collector _(T-271)_ | 📋 fila #10 |
| 3 | T-272…T-275 | YouTube, relevance gate, digest | backlog |
