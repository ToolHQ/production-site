# T-194: Cursor agent isolation — worktree, CURSOR-QUEUE, AI Radar owners

- **Status**: In Progress
- **Priority**: 🔼 High
- **Epic/Owner**: DevExp / Ops
- **Estimation**: 2h

## Context

Copilot e Antigravity já isolados (`production-site-copilot`, `production-site-antigravity`, PR #105). O Cursor ainda usava `~/production-site` compartilhado, gerando risco de conflito com outros agentes.

Objetivo: worktree dedicada, fila `CURSOR-QUEUE.md` (sem duplicar KANBAN), owners **Cursor / AI Radar** em todas as tasks do épico, loop documentado e `auto_loop.sh` com filtro `AGENT_OWNER`.

## Tasks

- [x] Criar worktree `~/production-site-cursor` (`feat/cursor-agent-isolation`)
- [x] Adicionar `tasks/CURSOR-QUEUE.md` + `docs/agent-orchestration.md`
- [x] Workflow `.agents/workflows/cursor_loop.md` + regra `.cursor/rules/cursor-worktree.mdc`
- [x] Atualizar `AGENTS.md`, `dev-worktrees.md`, `manage-tasks` skill, `COPILOT-QUEUE` cross-ref
- [x] `auto_loop.sh`: filtro `AGENT_OWNER` + workflow por agente
- [x] KANBAN: owners AI Radar In Progress/Backlog → `Cursor / AI Radar`
- [ ] PR mergeado; usuário abre pasta `production-site-cursor` no Cursor IDE
- [ ] Comunicar Copilot/Antigravity: não tocar `apps/ai-radar/` sem handoff

## Validação

```bash
git worktree list | grep cursor
AGENT_OWNER=Cursor WORKSPACE_DIR=~/production-site-cursor ./.agents/scripts/auto_loop.sh --dry-run
# Esperado: T-191 ou T-173 (In Progress, Owner Cursor)
```
