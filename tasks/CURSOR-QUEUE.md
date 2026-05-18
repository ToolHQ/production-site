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
| — | _(aguardando próximo epic AI Radar)_ | — |

## Fase 20 — (próximo)

> Definir no KANBAN após priorização.

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

**Ordem:** T-247 → T-248 → T-249 → T-250 → T-251 → T-252 — **concluída**.

**Flags:** `EMBEDDINGS_ENABLED` default `false`; sem pgvector obrigatório no MVP.

## Fase 18 — Inteligência operacional no console ✅

| # | ID | Tarefa | Status |
| -: | :- | :----- | :----- |
| 1–6 | T-241…246 | Digest v2, sinais, relatórios, filtros, compare, metadata | ✅ PR #224 |

## Fase 17 — Curadoria, sinais e ranking ✅

T-232, T-231, T-233, T-234, T-235, T-238, T-237, T-236, T-168, T-167 — todas ✅.

## Micro-tasks (sem T-ID)

- [x] Fase 18 deploy tag `1779057613`
- [x] Console https://ai-radar.dnor.io/ (Explorer, relatórios, digests v2)
- [x] Fase 19 deploy tag `1779065738` (search, related, semantic-duplicates, cronjob-embed)
- [x] Migrações Postgres `0005`–`0007` (entity resolution, snapshots, item_embeddings)
- [x] Secret `ai-radar-llm`: `EMBEDDINGS_ENABLED=true`, `EMBEDDING_MODEL=openai/text-embedding-3-small`
- [x] **T-254** Deploy CLI com `embed` — tags `1779070701`, 20 embeddings, search semântico OK
- [x] Recuperar **k8s-node-2** + Nexus; registry `31444` OK

## Concluídas (histórico recente)

| ID / Ref | Tarefa | Data |
| :------- | :----- | :--- |
| T-254 | Embed CLI deploy + smoke cluster — tag `1779070701` | 2026-05-18 |
| T-247–252 | Fase 19 — PRs #231, #235, #236, #237 | 2026-05-17 |
| T-241–246 | Fase 18 — PR #224, KANBAN #226 | 2026-05-17 |
| T-167 | LLM scorer — PR #221 | 2026-05-17 |
| T-177 | Explorer — PR #127 | 2026-05-16 |
