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
4. **Demo pipeline** — fontes + extract LLM + digest com conteúdo no console
5. ~~**T-177**~~ — Items API + Explorer UI ✅

## Em andamento (sessão atual)

| ID / Ref | Tarefa | Tipo |
| :------- | :----- | :--- |
| Demo pipeline | Encher digest no console (fontes + CronJobs + LLM) | micro |

## Próximas (prioridade Cursor — AI Radar)

| ID | Tarefa | Kanban |
| :- | :----- | :----- |
| T-162 | GitHub collector | Backlog |
| T-163 | Webpage fetcher | Backlog |
| T-167 | Scorer LLM opcional | Backlog |
| T-168 | Comparator | Backlog |

> Infra compartilhada (ex. T-193) permanece `Owner: Infra / Ops` — Cursor pode executar se pedido, mas não é fila padrão.

## Micro-tasks (sem T-ID)

- [x] T-175 deploy + console em https://ai-radar.dnor.io/
- [x] T-176 observability pack (Grafana JSON + README + smoke Prometheus Coroot)
- [x] Montar `ai-radar-llm` no Deployment da API — PR [#122](https://github.com/ToolHQ/production-site/pull/122)
- [x] Demo pipeline: digest semanal com itens **Testar** no console
- [x] Causa raiz `read-only transaction`: `postgres-service` → réplica; fix primário + reconcile `extracting`
- [x] Deploy T-177 API `1778974766` + explorer https://ai-radar.dnor.io/#/items
- [x] CLI CronJobs `1778965790` (reconcile extract)
- [x] Postgres entrypoint ConfigMap (hostNetwork + POD_NAME)

## Concluídas (histórico recente)

| ID / Ref | Tarefa | Data |
| :------- | :----- | :--- |
| T-170 | Feedback loop — testes + README — PR fechamento | 2026-05-16 |
| T-173 | Hardening — chaos Postgres + Done | 2026-05-16 |
| T-200 | BuildKit/cargo-chef validado | 2026-05-16 |
| T-177 | Items API + Explorer — PR [#127](https://github.com/ToolHQ/production-site/pull/127) | 2026-05-16 |
| T-176 | Dashboard pack Coroot/Grafana | 2026-05-16 |
| T-175 | Operator Console — PR [#116](https://github.com/ToolHQ/production-site/pull/116) | 2026-05-16 |
| T-173 deploy | Cluster tag `1778959644` | 2026-05-16 |
| T-191 | Smoke cluster + runbook | 2026-05-16 |
