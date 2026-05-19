# Cursor Queue — AI Radar & cluster ops

> **Fila de trabalho exclusiva do Cursor.** `tasks/KANBAN.md` = fonte de T-IDs.
> **Regra:** uma task por PR; **não** atacar Fase 22 e 23 em paralelo no mesmo deploy.

## Em andamento

| ID | Tarefa |
| :- | :----- |
| **T-263** | Metrics scrape resilience |

## Fase 22 — Resiliência backend (prioridade)

| # | ID | Tarefa | Status |
| -: | :- | :----- | :----- |
| 1 | T-263 | Metrics cache + stale gauges | 🏎️ |
| 2 | T-264 | Readiness probe DB | 📋 |
| 3 | T-265 | API graceful degradation | 📋 |
| 4 | T-266 | Pipeline SLO runbook | 📋 |

## Fase 23 — Fontes & trends (após Fase 22)

| # | ID | Tarefa | Est. |
| -: | :- | :----- | ---: |
| 1 | T-267 | RSS audit + taxonomia | 3h |
| 2 | T-268 | Curated vendor RSS pack | 4h |
| 3 | T-269 | AI tools watchlist (Cursor, Copilot, …) | 6h |
| 4 | T-270 | LLM models & pricing monitor | 6h |
| 5 | T-271 | Google Trends spike | 4h |
| 6 | T-272 | YouTube AI trends | 6h |
| 7 | T-273 | Collect relevance gate | 5h |
| 8 | T-274 | Sources console UX | 4h |
| 9 | T-275 | Digest AI Tools Pulse | 4h |

## Fase 21 ✅ | Fase 20 ✅

T-259–262 concluídas. Cobertura ~**91%**.

## Diagnóstico fontes (prod)

Feeds atuais são **demo/genéricos** (HN, Lobsters, Pragmatic Engineer) — T-267 formaliza troca por pack IA.
