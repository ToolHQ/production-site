---
description: Cursor Loop — Sessão no Cursor IDE, isolada de Copilot e Antigravity. Owner de AI Radar.
---

# Cursor Execution Loop

**Goal**: Executar tasks do épico **AI Radar** (e infra solicitada) sem conflitar com Copilot/Antigravity.
**Contexto**: Sessão no Cursor; pode ser manual ou orquestrada por `auto_loop.sh` com `AGENT_OWNER=Cursor`.

---

## Fase 1 — Orientação

1. **Worktree**: Operar **somente** em `~/production-site-cursor`.
   ```bash
   git worktree list | grep production-site-cursor
   ```
2. **Sync**: Antes de branch nova:
   ```bash
   cd ~/production-site-ops && git pull origin main
   cd ~/production-site-cursor && git fetch origin && git rebase origin/main
   ```
3. **Filas**: Ler `tasks/CURSOR-QUEUE.md` (sessão) e `tasks/KANBAN.md` (T-IDs).
4. **Pick rule**: Só tasks com `Owner` contendo **`Cursor`** ou epic **AI Radar** atribuído a Cursor no KANBAN.
5. **Skills**: `connect-to-cluster`, `deploy-service`, `manage-tasks`, `operational-safety` conforme o escopo.

---

## Fase 2 — Execução

1. Branch: `feat/T-XXX-descricao-curta` a partir de `origin/main`.
2. Escopo único por task; atualizar checkboxes no `tasks/2026/.../T-XXX-*.md`.
3. **Pré-voo deploy** (AI Radar): disco no master ≥ 12 GiB (`deploy.sh` pré-voo); ver `deploy-service` skill.
4. **Verificar**: harness path-aware, `kubectl` dry-run, smoke HTTP no cluster quando aplicável.
5. **Deploy**: Rodar `./deploy.sh` você mesmo — não delegar ao operador.

---

## Fase 3 — Entrega

1. Commit + push na worktree Cursor.
2. `gh pr create` → `gh pr checks` → merge (API se `main` bloqueada em outro worktree).
3. `manage_tasks.sh done T-XXX` + atualizar `CURSOR-QUEUE.md`.
4. Handoff em `.agents/progress.txt` se houver bloqueio para outro agente.

---

## Ralph / auto-loop (opcional)

```bash
cd ~/production-site-cursor
AGENT_OWNER='Cursor' WORKSPACE_DIR="$PWD" ./.agents/scripts/auto_loop.sh --dry-run
```

O script filtra KANBAN por substring no campo **Owner**. Não usar o loop genérico sem `AGENT_OWNER` — evita roubar tasks de Copilot/Antigravity.

---

## O que Cursor **não** faz

- Editar arquivos em `~/production-site-copilot` ou `~/production-site-antigravity`.
- Mover tasks AI Radar para Done sem evidência (deploy/smoke/logs).
- Commit em `main` ou push `--force` em branches compartilhadas.
