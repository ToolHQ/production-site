# Orquestração multi-agente — KANBAN, filas e loops (ralph)

Quatro agentes trabalham em paralelo neste repositório. O desenho evita **duplicar** o Kanban e **conflitar** em arquivos Git.

## Fonte de verdade

| Artefato | Papel |
| -------- | ----- |
| `tasks/KANBAN.md` | **Único** board de T-IDs (Backlog / In Progress / Done) |
| `tasks/CURSOR-QUEUE.md` | Sprint Cursor — prioriza AI Radar; micro-tasks sem T-ID |
| `tasks/COPILOT-QUEUE.md` | Sprint Copilot — micro-tasks e refs T-ID Copilot |
| `tasks/CODEX-QUEUE.md` | Sprint Codex — coordenação, infra/tooling e micro-tasks sem T-ID |
| `tasks/2026/.../T-XXX-*.md` | Especificação e checklist de cada T-ID |

**Não** criar segundo KANBAN. Filas de agente **referenciam** T-IDs existentes.

## Mapa de worktrees

| Diretório | Branch típica | Agente | Fila |
| --------- | ------------- | ------ | ---- |
| `~/production-site-cursor` | `feat/cursor-*`, `feat/T-19*` | **Cursor** | `CURSOR-QUEUE.md` + KANBAN (`Cursor / AI Radar`) |
| `~/production-site-copilot` | `feat/copilot-*` | **Copilot/VSCode** | `COPILOT-QUEUE.md` + KANBAN (`Copilot/VSCode`) |
| `~/production-site-antigravity` | `feat/agent-loop` | **Antigravity** | KANBAN (`Antigravity`) |
| `~/production-site-rust-rover-claude` | `feat/T-*`, `codex/*` | **Codex / Rust Rover** | `CODEX-QUEUE.md` + KANBAN (`Codex`) |
| `~/production-site-ops` | `main` | Merge / leitura | — |

> `~/production-site` (checkout legado): migrar sessões Cursor para `production-site-cursor`.

## Campo Owner no KANBAN

- Cada linha da tabela tem coluna **Owner**.
- Agente só **start/done** em tasks onde é owner (ou epic explicitamente atribuído).
- **Cursor**: todas as tasks **AI Radar** → `Cursor / AI Radar`.
- **Copilot**: tasks com `Copilot/VSCode` no Owner.
- **Antigravity**: tasks com `Antigravity` no Owner.
- **Codex / Rust Rover**: tasks com `Codex` no Owner; infra/tooling compartilhado só com handoff explícito.
- Infra compartilhada (`Infra / Ops`, `DevExp / Tooling`) — negociar no chat; não assumir sem Owner.

## Loops de execução (ralph)

| Agente | Workflow | Modo |
| ------ | -------- | ---- |
| Cursor | [`.agents/workflows/cursor_loop.md`](../.agents/workflows/cursor_loop.md) | Interativo + opcional `auto_loop.sh` |
| Copilot | [`.agents/workflows/copilot_loop.md`](../.agents/workflows/copilot_loop.md) | Interativo VSCode |
| Antigravity | [`.agents/workflows/auto_loop_execution.md`](../.agents/workflows/auto_loop_execution.md) | Headless |
| Codex / Rust Rover | [`.agents/workflows/codex_loop.md`](../.agents/workflows/codex_loop.md) | Autopilot assistido |

Script compartilhado: `.agents/scripts/auto_loop.sh` (inspirado em [snarktank/ralph](https://github.com/snarktank/ralph)).

```bash
# Simular próxima task Cursor
cd ~/production-site-cursor
AGENT_OWNER='Cursor' WORKSPACE_DIR="$PWD" ./.agents/scripts/auto_loop.sh --dry-run
```

```bash
# Simular próxima task Codex
cd ~/production-site-rust-rover-claude
AGENT_OWNER='Codex' WORKSPACE_DIR="$PWD" ./.agents/scripts/auto_loop.sh --dry-run
```

## Regras anti-conflito

1. **Um agente por worktree** — sem edits cross-directory.
2. **Pull antes de push** em `KANBAN.md`, `AGENTS.md`, `CHANGELOG.md`.
3. **GitFlow** — PR para `main`; merge via `gh` ou API.
4. Micro-tasks sem T-ID **não** entram no KANBAN — só na fila do agente.
5. Mover card no KANBAN com `./tools/manage_tasks.sh start|done T-XXX`.

## AI Radar — ownership Cursor

Épico inteiro sob Cursor: deploy, smoke (T-191), hardening (T-173), collectors backlog (T-162…T-170).

Copilot/Antigravity: não alterar `apps/ai-radar/` nem tasks AI Radar sem handoff explícito no chat.

## Cluster Pulse — ownership Antigravity

Durante a frente T-195, Antigravity é owner de `apps/rs-observability-api/web-v2/`.

Codex/Cursor/Copilot: não alterar a UI do Cluster Pulse sem handoff explícito no chat.
