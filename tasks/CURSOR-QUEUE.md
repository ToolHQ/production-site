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

1. **T-173** — fechar fatia restante (MAX_CONCURRENT_LLM, chaos Postgres, HTML sanitize) _em paralelo se não bloquear UI_
2. **T-175** — Operator Console (**em andamento**)
3. **T-176** — Dashboard pack Coroot/Grafana
4. Demo pipeline no cluster (fontes + CronJobs + digest com conteúdo)
5. **T-177** — Items API + Explorer UI

## Em andamento (sessão atual)

| ID / Ref | Tarefa | Tipo |
| :------- | :----- | :--- |
| [T-175](2026/Q2/T-175-AI-Radar-Operator-Console-Thin-Slice.md) | Operator Console — UI em `ai-radar.dnor.io` | T-ID |
| [T-173](2026/Q2/T-173-AI-Radar-Hardening.md) | Hardening — PR [#109](https://github.com/dnorio/production-site/pull/109) mergeado; backlog restante | T-ID |

## Próximas (prioridade Cursor — AI Radar)

| ID | Tarefa | Kanban |
| :- | :----- | :----- |
| T-176 | Dashboard pack Coroot/Grafana | Backlog |
| T-177 | Items API + Explorer UI | Backlog |
| T-162 | GitHub collector | Backlog |
| T-163 | Webpage fetcher | Backlog |
| T-167 | Scorer LLM opcional | Backlog |
| T-168 | Comparator | Backlog |
| T-170 | Feedback loop | Backlog |

> Infra compartilhada (ex. T-193) permanece `Owner: Infra / Ops` — Cursor pode executar se pedido, mas não é fila padrão.

## Micro-tasks (sem T-ID)

- [x] Após deploy: checar disco master + prune BuildKit se necessário (T-193)
- [x] Validar `POST /digest/run` e `/metrics` com `ai_radar_*` (T-191)
- [x] Redeploy T-173 — tag `1778953197` (API+CLI), rollout OK
- [x] Smoke `POST /items/:id/reprocess` stage `score` → 200 + `scored: true`
- [x] Roadmap Fase 16 + tasks T-175/T-176/T-177 no KANBAN
- [ ] API Deployment: montar `ai-radar-llm` (CronJobs já têm; API para extract/reprocess `all`)
- [ ] Demo pipeline: fonte RSS + collect + extract + digest com conteúdo visível no console

## Concluídas (histórico recente)

| ID / Ref | Tarefa | Data |
| :------- | :----- | :--- |
| T-173 deploy | Cluster tag `1778953197` + smoke reprocess/digest/metrics | 2026-05-16 |
| T-191 | Smoke cluster + runbook + deploy tag `1778940768` | 2026-05-16 |
| T-193 | Master rootfs cleanup (executado no cluster) | 2026-05-16 |
| #106 | Isolamento Cursor (worktree + CURSOR-QUEUE) | 2026-05-16 |
| #102, #103 | Docs + pré-voo deploy | 2026-05-16 |
