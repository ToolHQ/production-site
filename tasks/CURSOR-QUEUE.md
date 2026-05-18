# Cursor Queue — AI Radar & cluster ops

> **Fila de trabalho exclusiva do Cursor.**
> O `KANBAN.md` continua como **única fonte de verdade** para tarefas T-ID.
> Este arquivo é o _sprint board_ da sessão Cursor — não duplica status, apenas prioriza e registra micro-tasks.

## Regras de uso

- **Cursor** opera em `~/production-site-cursor` (worktree dedicada).
- **Cursor** é owner de **todas** as tasks **AI Radar** no `KANBAN.md` (`Owner` contém `Cursor / AI Radar`).
- **Copilot/VSCode** e **Antigravity** não pegam tasks com `Owner: Cursor` nem epic AI Radar em andamento.
- Micro-tasks (< 30 min, sem T-ID) ficam **só aqui**; ao concluir, marcar `[x]` — sem linha extra no KANBAN.
- Tarefas T-ID: branch `feat/T-XXX-…` nesta worktree → PR → merge (GitFlow).

## Em andamento (sessão atual)

| ID / Ref | Tarefa | Tipo |
| :------- | :----- | :--- |
| **T-255** | Embedding coverage stats | Fase 20 |

## Fase 20 — Semântica em produção

> **Tema:** cobertura de embeddings visível, backfill operável, UX de vizinhança/duplicatas; sem pgvector nem auto-merge.

| # | ID | Tarefa | Prioridade | Status |
| -: | :- | :----- | :--------- | :----- |
| 1 | **T-255** | Embedding coverage stats (`/stats`, metrics, console) | 🔼 High | 🏎️ |
| 2 | **T-256** | Embed batch scale & backfill ops | 🔼 High | 📋 |
| 3 | **T-257** | Related items & semantic empty-state UX | 🔼 High | 📋 |
| 4 | **T-258** | Semantic duplicates console drill-down | 🔽 Low | 📋 |

**Ordem:** T-255 → T-256 → T-257 → T-258.

## Fase 19 — Semântica leve (embeddings & busca) ✅

> **Tema:** embeddings self-hosted via gateway existente; busca semântica e related items; dedup semântico só como relatório.

| # | ID | Tarefa | Prioridade | Status |
| -: | :- | :----- | :--------- | :----- |
| 1 | **T-247** | Embedding provider & schema | 🔼 High | ✅ PR #231 |
| 2 | **T-248** | Embed pipeline pós-extract | 🔼 High | ✅ PR #235 |
| 3 | **T-249** | Semantic search API | 🔼 High | ✅ PR #236 |
| 4 | **T-250** | Explorer search UI | 🔼 High | ✅ PR #236 |
| 5 | **T-251** | Related items no detalhe | 🔼 High | ✅ PR #237 |
| 6 | **T-252** | Relatório duplicate clusters semânticos | 🔽 Low | ✅ PR #237 |
| — | **T-254** | Deploy CLI embed + smoke cluster | 🔼 High | ✅ PR #244 |

**Ordem:** T-247 → T-248 → T-249 → T-250 → T-251 → T-252 → T-254 — **concluída**.

## Fase 18 — Inteligência operacional no console ✅

| # | ID | Tarefa | Status |
| -: | :- | :----- | :----- |
| 1–6 | T-241…246 | Digest v2, sinais, relatórios, filtros, compare, metadata | ✅ PR #224 |

## Fase 17 — Curadoria, sinais e ranking ✅

T-232, T-231, T-233, T-234, T-235, T-238, T-237, T-236, T-168, T-167 — todas ✅.

## Micro-tasks (sem T-ID)

- [x] Fase 19 deploy tag `1779070701` (search, embed CLI, 20 embeddings)
- [x] Secret `ai-radar-llm`: embeddings habilitados
- [ ] Backfill embeddings até cobertura >80% (pós T-256)

## Concluídas (histórico recente)

| ID / Ref | Tarefa | Data |
| :------- | :----- | :--- |
| T-254 | Embed CLI deploy + smoke cluster | 2026-05-18 |
| T-247–252 | Fase 19 — PRs #231, #235, #236, #237 | 2026-05-17 |
| T-241–246 | Fase 18 — PR #224 | 2026-05-17 |
