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
| `feat/cursor-agent-isolation` | Worktree Cursor + CURSOR-QUEUE + owners AI Radar + loop | Meta/Ops |
| [T-191](2026/Q2/T-191-AI-Radar-Cluster-Smoke-Demo-Runbook-post-T-169.md) | Smoke cluster pós-deploy | T-ID |
| [T-173](2026/Q2/T-173-AI-Radar-Hardening.md) | Hardening | T-ID |

## Próximas (prioridade Cursor — AI Radar)

| ID | Tarefa | Kanban |
| :- | :----- | :----- |
| T-191 | Fechar smoke/deploy runbook | In Progress |
| T-173 | Hardening (retry, chaos, versioning) | In Progress |
| T-162 | GitHub collector | Backlog |
| T-163 | Webpage fetcher | Backlog |
| T-167 | Scorer LLM opcional | Backlog |
| T-168 | Comparator | Backlog |
| T-170 | Feedback loop | Backlog |

> Infra compartilhada (ex. T-193) permanece `Owner: Infra / Ops` — Cursor pode executar se pedido, mas não é fila padrão.

## Micro-tasks (sem T-ID)

- [ ] Após cada `apps/ai-radar/deploy.sh`: checar `df -h /` no master + prune BuildKit se cache > 10 GiB
- [ ] Validar `POST /digest/run` e `/metrics` com `ai_radar_*` após rollout

## Concluídas (histórico recente)

| ID / Ref | Tarefa | Data |
| :------- | :----- | :--- |
| T-193 | Master rootfs cleanup (executado no cluster) | 2026-05-16 |
| #102, #103 | Docs smoke + pré-voo deploy | 2026-05-16 |
