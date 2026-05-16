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
| [T-173](2026/Q2/T-173-AI-Radar-Hardening.md) | Hardening | T-ID |

## Próximas (prioridade Cursor — AI Radar)

| ID | Tarefa | Kanban |
| :- | :----- | :----- |
| T-173 | Hardening (retry, chaos, versioning) | In Progress |
| T-162 | GitHub collector | Backlog |
| T-163 | Webpage fetcher | Backlog |
| T-167 | Scorer LLM opcional | Backlog |
| T-168 | Comparator | Backlog |
| T-170 | Feedback loop | Backlog |

> Infra compartilhada (ex. T-193) permanece `Owner: Infra / Ops` — Cursor pode executar se pedido, mas não é fila padrão.

## Micro-tasks (sem T-ID)

- [x] Após deploy: checar disco master + prune BuildKit se necessário (T-193)
- [x] Validar `POST /digest/run` e `/metrics` com `ai_radar_*` (T-191)

## Concluídas (histórico recente)

| ID / Ref | Tarefa | Data |
| :------- | :----- | :--- |
| T-191 | Smoke cluster + runbook + deploy tag `1778940768` | 2026-05-16 |
| T-193 | Master rootfs cleanup (executado no cluster) | 2026-05-16 |
| #106 | Isolamento Cursor (worktree + CURSOR-QUEUE) | 2026-05-16 |
| #102, #103 | Docs + pré-voo deploy | 2026-05-16 |
