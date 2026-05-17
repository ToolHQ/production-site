# Codex / Rust Rover Queue

> Fila exclusiva do Codex no Rust Rover.
> O `tasks/KANBAN.md` continua sendo a fonte de verdade para T-IDs.

## Regras de Uso

- Codex opera em `~/production-site-rust-rover-claude`.
- Codex trabalha em tasks com `Owner` contendo `Codex` ou em tarefas `Infra / Ops` e `DevExp / Tooling` quando houver handoff explícito no chat.
- Codex não altera `apps/ai-radar/` enquanto Cursor estiver owner da frente AI Radar.
- Codex não altera `apps/rs-observability-api/web-v2/` enquanto Antigravity estiver owner da frente Cluster Pulse.
- Copilot/VSCode mantém ownership de `tasks/COPILOT-QUEUE.md` e tasks com `Owner: Copilot/VSCode`.
- Micro-tasks de Codex ficam só neste arquivo; T-IDs ficam no KANBAN.

## Em Andamento

| ID / Ref | Tarefa | Tipo |
| :------- | :----- | :--- |
| — | — | — |

## Próximas

| ID / Ref | Tarefa | Prioridade |
| :------- | :----- | :--------- |
| T-192 | Control Plane Hardening, somente após check de cluster e sem ação destrutiva sem confirmação explícita | 🚨 Critical |
| T-142/T-144/T-147 | Quality gates pequenos e sem overlap com produto | 🔼 High |

## Micro-Tasks

- [x] Isolar `~/production-site-rust-rover-claude` em worktree própria partindo de `origin/main`.
- [x] Validar que `.agents/scripts/auto_loop.sh --dry-run` filtra `Owner: Codex`.
- [x] Registrar limites de autopilot e comandos que ainda exigem aprovação por sandbox.

## Concluídas

| Ref | Tarefa | Data |
| :-- | :----- | :--- |
| T-202 | Codex worktree isolation and autopilot coordination | 2026-05-16 |
