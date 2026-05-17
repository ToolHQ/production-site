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

## Ordem aprovada (Fase 16 + hardening)

1. ~~**T-173**~~ — Hardening ✅
2. ~~**T-175**~~ — Console ✅
3. ~~**T-176**~~ — Dashboards ops ✅
4. ~~**Demo pipeline**~~ — fontes + extract LLM + digest no console ✅
5. ~~**T-177**~~ — Items API + Explorer UI ✅

## Em andamento (sessão atual)

| ID / Ref | Tarefa | Tipo |
| :------- | :----- | :--- |
| **T-235** | Explorer ranking & badges (adoption no Explorer) | feat |

## Fase 17 — Curadoria, sinais e ranking

| # | ID | Tarefa | Status |
| -: | :- | :----- | :----- |
| 1 | **T-232** | Extract quality gate | ✅ PR #193 |
| 2 | **T-231** | Entity resolution / dedup | ✅ PR #198 |
| 3 | **T-233** | Adoption signals (GitHub → score) | ✅ PR #200 |
| 4 | **T-234** | Popularity velocity & snapshots | ✅ PR #211 |
| 5 | **T-235** | Explorer ranking & badges | ✅ PR #208 |
| 6 | **T-238** | Source health / noise | ✅ PR #215 |
| 7 | **T-237** | Comparator no console | ✅ PR #217 |
| 8 | **T-236** | Feedback-calibrated scoring v2 | ✅ PR #218 |

> **Nota IDs:** `T-233` no repo = adoption (antes planejado como velocity no stash). Velocity = **T-234**. UI premium console = PR #203.

## Próximas (backlog legado)

| ID | Tarefa | Kanban |
| :- | :----- | :----- |
| T-167 | Scorer LLM opcional | ✅ PR #159 |

> **T-168** Comparator ✅ Done. Infra compartilhada = `Owner: Infra / Ops`.

## Micro-tasks (sem T-ID)

- [x] T-175 deploy + console em https://ai-radar.dnor.io/
- [x] T-176 observability pack (Grafana JSON + README + smoke Prometheus Coroot)
- [x] Console UI premium restaurada — PR #203, deploy `1779049513`
- [x] Montar `ai-radar-llm` no Deployment da API — PR [#122](https://github.com/ToolHQ/production-site/pull/122)
- [x] Demo pipeline: digest semanal com itens **Testar** no console
- [x] Deploy T-177 API + explorer https://ai-radar.dnor.io/#/items
- [x] Postgres entrypoint ConfigMap (hostNetwork + POD_NAME)

## Concluídas (histórico recente)

| ID / Ref | Tarefa | Data |
| :------- | :----- | :--- |
| T-203 | Console UI premium (merge + deploy) | 2026-05-17 |
| T-233 | Adoption signals | 2026-05-17 |
| T-231 | Entity resolution | 2026-05-17 |
| T-232 | Extract quality gate | 2026-05-17 |
| T-168 | Comparator — PR #162 | 2026-05-17 |
| T-162 | GitHub collector | 2026-05-17 |
| T-163 | Webpage fetcher | 2026-05-17 |
| T-177 | Items API + Explorer — PR #127 | 2026-05-16 |
| T-175 | Operator Console — PR #116 | 2026-05-16 |
