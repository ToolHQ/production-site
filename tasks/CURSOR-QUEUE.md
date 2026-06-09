# Cursor Queue — AI Radar & cluster ops

> **Sincronizado**: 2026-06-09 · branch `feat/t-363-google-trends` · KANBAN = fonte de T-IDs

## Próximas 10 (ordem de execução)

| # | ID | Tarefa | Prioridade | Status |
| -: | :- | :----- | :--------- | :----- |
| 1 | **T-348** | Jenkins deploy-apps job parametrizado | 🔼 High | 🏎️ **próximo** |
| 2 | **T-306** | OCI health watchdog env permission + alertas | 🔼 High | 🏎️ |
| 4 | **T-311** | Hetzner BuildKit disk growth guardrails | 🚨 Critical | 📋 |
| 5 | **T-307** | OCI Longhorn disk headroom + política preventiva | 🔼 High | 📋 |
| 6 | **T-302** | qdbback TLS/Prometheus/AL2023 | 🔵 Medium | 🏎️ |

## Concluído neste sprint

| # | ID | Tarefa | Status |
| -: | :- | :----- | :----- |
| 1 | **T-362a** | Postgres email-intelligence K8s + RLS — harness PASS | ✅ |
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

## Fase 23 — Fontes & trends (AI Radar)

| # | ID | Tarefa | Status |
| -: | :- | :----- | :----- |
| 1 | T-267…T-270 | RSS, vendors, watchlist, models | ✅ |
| 2 | **T-363** | Google Trends Collector _(T-271)_ | 📋 fila #10 |
| 3 | T-272…T-275 | YouTube, relevance gate, digest | backlog |
