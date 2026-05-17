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
| **T-241..246** | Fase 18 — em PR | feat |

## Fase 17 — Curadoria, sinais e ranking ✅

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
| 9 | **T-168** | Comparator (core) | ✅ |
| 10 | **T-167** | Scorer LLM opcional | ✅ PR #221 |

> **Nota IDs:** `T-233` no repo = adoption. Velocity = **T-234**. UI premium console = PR #203.

## Fase 18 — Inteligência operacional no console

> **Tema:** levar sinais da Fase 17 ao digest, Explorer e relatórios — sem embeddings (fase futura).

| # | ID | Tarefa | Prioridade | Status |
| -: | :- | :----- | :--------- | :----- |
| 1 | **T-241** | Digest v2 — trending, adoção, fontes ruidosas | 🔼 High | 🏎️ PR |
| 2 | **T-242** | Explorer — painel de sinais no detalhe | 🔼 High | 🏎️ PR |
| 3 | **T-243** | Console — duplicatas & divergência | 🔼 High | 🏎️ PR |
| 4 | **T-244** | Explorer — filtros velocity / health / quality | 🔼 High | 🏎️ PR |
| 5 | **T-245** | Compare deep-link & categoria | 🔽 Low | 🏎️ PR |
| 6 | **T-246** | Digest metadata + stats strip (`GET /stats`) | 🔽 Low | 🏎️ PR |

**Ordem de execução recomendada:** T-241 → T-242 → T-243 → T-244 → T-245 → T-246.

## Micro-tasks (sem T-ID)

- [x] T-175 deploy + console em https://ai-radar.dnor.io/
- [x] T-176 observability pack (Grafana JSON + README + smoke Prometheus Coroot)
- [x] Console UI premium restaurada — PR #203, deploy `1779049513`
- [x] Montar `ai-radar-llm` no Deployment da API — PR [#122](https://github.com/ToolHQ/production-site/pull/122)
- [x] Demo pipeline: digest semanal com itens **Testar** no console
- [x] Deploy T-177 API + explorer https://ai-radar.dnor.io/#/items
- [x] Postgres entrypoint ConfigMap (hostNetwork + POD_NAME)
- [x] Fase 17 fechada — deploy consolidado tag `1779054856`

## Concluídas (histórico recente)

| ID / Ref | Tarefa | Data |
| :------- | :----- | :--- |
| T-167 | LLM scorer closeout — PR #221 | 2026-05-17 |
| T-236–238 | Calibração, comparator UI, source health | 2026-05-17 |
| T-234 | Velocity & snapshots — PR #211 | 2026-05-17 |
| T-203 | Console UI premium (merge + deploy) | 2026-05-17 |
| T-233 | Adoption signals | 2026-05-17 |
| T-231 | Entity resolution | 2026-05-17 |
| T-232 | Extract quality gate | 2026-05-17 |
| T-168 | Comparator — PR #162 | 2026-05-17 |
| T-177 | Items API + Explorer — PR #127 | 2026-05-16 |
| T-175 | Operator Console — PR #116 | 2026-05-16 |
