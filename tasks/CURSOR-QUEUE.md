# Cursor Queue — AI Radar & cluster ops

> **Sincronizado**: 2026-06-09 · branch `feat/cursor-hygiene-queue-t350` · KANBAN = fonte de T-IDs

## Próximas 10 (ordem de execução)

| # | ID | Tarefa | Prioridade | Status |
| -: | :- | :----- | :--------- | :----- |
| 1 | **T-342** | SSDNodes CI — bump Sonar 26.6 + Jenkins 2.567 JDK25 | 🔼 High | 🏎️ **próximo** |
| 2 | **T-343** | Jenkins reverse proxy + security hardening | 🔼 High | 🏎️ |
| 3 | **T-346** | citools deploy catalog + CLI (`list/plan/run`) | 🔼 High | 📋 |
| 4 | **T-361** | SSDNodes — n8n Docker (latest, auth, TLS, `n8n.ssdnodes.dnor.io`) | 🔼 High | 📋 |
| 5 | **T-362** | n8n + Ollama — email classification (**research/specs only**) | 🚨 Critical | 📋 _(após T-361)_ |
| 6 | **T-347** | Deploy workers Hetzner / OCI / SSDNodes | 🔼 High | 📋 |
| 7 | **T-348** | Jenkins deploy-apps job parametrizado | 🔼 High | 📋 |
| 8 | **T-304** | OCI MinIO backup capacity headroom + retention IaC/TUI | 🚨 Critical | 🏎️ |
| 9 | **T-305** | OCI logrotate rsyslog-aggressive duplicado em IaC/TUI | 🚨 Critical | 🏎️ |
| 10 | **T-363** | AI Radar — Google Trends Collector (implementa T-271) | 🔼 High | 📋 |

## Concluído neste sprint

| # | ID | Tarefa | Status |
| -: | :- | :----- | :----- |
| 1 | **T-341** | SSDNodes Jenkins + SonarQube CE (PR #394) | ✅ |
| 2 | **T-345** | GitHub branch protection + Jenkins webhook | ✅ |
| 3 | **T-349** | Jenkins Blue Ocean + Stage View UX | ✅ |

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
