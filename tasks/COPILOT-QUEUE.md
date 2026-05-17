# 📋 Copilot/VSCode Queue

> **Fila de trabalho exclusiva do GitHub Copilot (VSCode).**
> O `KANBAN.md` continua como **única fonte de verdade** para tarefas T-ID.
> Este arquivo funciona como _sprint board_ de sessão do Copilot — não duplica, apenas filtra e complementa.

## Regras de Uso

- **Copilot** só trabalha em tarefas onde `Owner` contém `Copilot/VSCode` no `KANBAN.md`, ou em micro-tasks listadas aqui.
- **Cursor** usa `tasks/CURSOR-QUEUE.md` e worktree `~/production-site-cursor` (owner **AI Radar** no KANBAN).
- **Cursor / Antigravity** não devem pegar tarefas com `Owner: Copilot/VSCode`.
- Micro-tasks (< 30 min, sem branch) ficam apenas aqui. Ao completar, marcam como `[x]` — sem mover para KANBAN.
- Tarefas T-ID exigem branch em `production-site-copilot` → PR → merge.

## 🏎️ Em Andamento (sessão atual)

| ID / Ref | Tarefa | Tipo |
| :------- | :----- | :--- |
| — | Housekeeping KANBAN + CronJob fix | micro |

## 📋 Próximas (Copilot/VSCode)

> Referenciar T-IDs do KANBAN.md (com `Owner: Copilot/VSCode`) ou micro-tasks.

| ID / Ref | Tarefa | Prioridade |
| :------- | :----- | :--------- |
| — | Monitorar estabilidade do cluster (node-1 disk 85%) | 🔽 Low |

## 🔬 Micro-Tasks (sem T-ID, sem PR)

> Itens rápidos de uma sessão. Ao concluir, marcar `[x]` aqui e commitá-los na branch corrente (se houver).

- [x] `kubectl delete pods -n kube-system --field-selector=status.phase=Failed` — limpar evicted
- [x] Deletar pods stale ContainerStatusUnknown (ai-radar, hubble-relay, failed-pod-cleaner)
- [x] Fix CronJob `failed-pod-cleaner` image: `bitnami/kubectl:1.31` → `registry.k8s.io/kubectl:v1.28.0`

## ✅ Concluídas (histórico recente)

| ID / Ref                      | Tarefa                                               | Data       |
| :---------------------------- | :--------------------------------------------------- | :--------- |
| [T-203](2026/Q2/T-203-Node-Fleet-Tooltip-Fixed-Positioning.md) | Node Fleet Tooltip Fixed Positioning (TooltipWrapper) | 2026-05-17 |
| [T-201](2026/Q2/T-201-Node-Fleet-Real-Machine-Metrics-Prometheus.md) | Node Fleet Real Machine Metrics via Prometheus | 2026-05-17 |
| [T-200](2026/Q2/T-200-Node-Fleet-Panel-Layout-Polish.md) | Node Fleet Panel Layout Polish | 2026-05-17 |
| [T-193](2026/Q2/T-193-Master-rootfs-cleanup-BuildKit-cache-legado-MinIO.md) | Master rootfs cleanup + hook prune pós-build | 2026-05-16 |
| `feat/copilot-infra-backlog`  | Triage infra/estabilidade: T-196/197/198 + KANBAN    | 2026-05-16 |
| `feat/copilot-task-structure` | Setup inicial: worktree + queue + loop workflow + PR | 2026-05-16 |
