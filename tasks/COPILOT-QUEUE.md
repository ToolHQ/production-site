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
| — | Audit completo Agent Meter — todas abas, filtros e reports | QA |

## 📋 Próximas (Copilot/VSCode)

> Referenciar T-IDs do KANBAN.md (com `Owner: Copilot/VSCode`) ou micro-tasks.

| ID / Ref | Tarefa | Prioridade |
| :------- | :----- | :--------- |
| [T-276](2026/Q2/T-276-Agent-Meter-Top-MCP-Servers-Semantic-Fix.md) | Fix Top MCP Servers: excluir llm_chat da query SQL | 🔼 High |
| [T-277](2026/Q2/T-277-Agent-Meter-Top-Tasks-Para-Top-Conversations.md) | Top Tasks → Top Conversations (agrupar por conversation_id) | 🔼 High |
| [T-279](2026/Q2/T-279-Agent-Meter-Duration-Humanizada.md) | Formatação humanizada de duração (ms → s/min) | 🔵 Medium |
| [T-278](2026/Q2/T-278-Agent-Meter-Metrics-Endpoint.md) | Endpoint /metrics — 404 (link morto no footer) | 🔵 Medium |
| [T-280](2026/Q2/T-280-Agent-Meter-Model-Filter-Em-Reports.md) | Filtro model global não afeta reports | 🔵 Medium |
| [T-281](2026/Q2/T-281-Agent-Meter-Sort-Colunas-Reports.md) | Sort interativo em colunas dos reports | 🟡 Low |
| — | Monitorar estabilidade do cluster | 🔽 Low |

## 🔬 Micro-Tasks (sem T-ID, sem PR)

> Itens rápidos de uma sessão. Ao concluir, marcar `[x]` aqui e commitá-los na branch corrente (se houver).

- [x] `kubectl delete pods -n kube-system --field-selector=status.phase=Failed` — limpar evicted
- [x] Deletar pods stale ContainerStatusUnknown (ai-radar, hubble-relay, failed-pod-cleaner)
- [x] Fix CronJob `failed-pod-cleaner` image: `bitnami/kubectl:1.31` → `registry.k8s.io/kubectl:v1.28.0`
- [x] T-263: Brand header (icon, title, subtitle, bg-glow, favicon, footer) — PR #262 merged
- [x] Fix max-width:220px em `td` quebrando column resize — PR #264 merged
- [x] Fix CONV ID substring(0,8) hardcoded no JS + IP substring(0,15) + click-to-filter — tag 1779188533
- [x] Audit completo Agent Meter (2025-07-14): todas abas, filtros, endpoints — criadas T-276 a T-281

## ✅ Concluídas (histórico recente)

| ID / Ref                      | Tarefa                                               | Data       |
| :---------------------------- | :--------------------------------------------------- | :--------- |
| [T-203](2026/Q2/T-203-Node-Fleet-Tooltip-Fixed-Positioning.md) | Node Fleet Tooltip Fixed Positioning (TooltipWrapper) | 2026-05-17 |
| [T-201](2026/Q2/T-201-Node-Fleet-Real-Machine-Metrics-Prometheus.md) | Node Fleet Real Machine Metrics via Prometheus | 2026-05-17 |
| [T-200](2026/Q2/T-200-Node-Fleet-Panel-Layout-Polish.md) | Node Fleet Panel Layout Polish | 2026-05-17 |
| [T-193](2026/Q2/T-193-Master-rootfs-cleanup-BuildKit-cache-legado-MinIO.md) | Master rootfs cleanup + hook prune pós-build | 2026-05-16 |
| `feat/copilot-infra-backlog`  | Triage infra/estabilidade: T-196/197/198 + KANBAN    | 2026-05-16 |
| `feat/copilot-task-structure` | Setup inicial: worktree + queue + loop workflow + PR | 2026-05-16 |
