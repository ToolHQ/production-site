---
description: Copilot/VSCode Loop — Sessão interativa no VSCode, isolada de Cursor e Antigravity.
---

# Copilot/VSCode Execution Loop

**Goal**: Executar tarefas atribuídas ao `Copilot/VSCode` de forma isolada dos outros agentes (Cursor, Antigravity).
**Contexto**: Executado interativamente pelo usuário via VSCode/Copilot Chat. Não é headless — a cada sessão o usuário conduz.

---

## Fase 1 — Orientação de Sessão

1. **Verificar worktree**: Confirmar que o Copilot está operando em `~/production-site-copilot`.
   ```bash
   git worktree list
   # Esperado: /home/ToolHQ/production-site-copilot [feat/...]
   ```
2. **Sincronizar main**: Antes de qualquer branch nova, atualizar `production-site-ops` (worktree de main) e garantir que `production-site-copilot` está baseado no `main` mais recente.
   ```bash
   cd ~/production-site-ops && git pull origin main
   ```
3. **Ler a fila**: Abrir `tasks/COPILOT-QUEUE.md` e identificar o item em andamento ou o próximo.
4. **Verificar KANBAN**: Para tarefas T-ID, ler `tasks/KANBAN.md` filtrando `Owner: Copilot/VSCode`.
5. **Lembrar contexto**: Ler `AGENTS.md` + `.agents/progress.txt` se houver handoffs de sessões anteriores.

---

## Fase 2 — Execução

### Para tarefas T-ID (entrada no KANBAN)

1. Criar branch a partir de main dentro da worktree Copilot:
   ```bash
   cd ~/production-site-copilot
   git checkout -b feat/{TASK_ID}-{descricao-curta}
   ```
2. Executar o trabalho. Restringir ao escopo da task.
3. **Verificar** imediatamente:
   - Sintaxe: `bash -n`, `python -m py_compile`, `tsc --noEmit`, `cargo check`
   - K8s: `kubectl apply --dry-run=client -f <file>`
   - Testes: conforme disponível em `scripts/` ou `Makefile`
4. Corrigir falhas dentro do mesmo contexto. Deixar o cluster em estado **Verde / Estável**.

### Para micro-tasks (apenas COPILOT-QUEUE.md)

1. Executar diretamente (edição de arquivo, script, consulta).
2. Se houver branch ativa, commitar junto. Se não, commit direto na branch de sessão.
3. Marcar `[x]` no `tasks/COPILOT-QUEUE.md`.

---

## Fase 3 — Entrega

1. Commitar as mudanças:
   ```bash
   git add .
   git commit -m "feat({TASK_ID}): <descrição>"
   ```
2. Push e abrir PR:
   ```bash
   git push -u origin feat/{TASK_ID}-{descricao-curta}
   gh pr create --title "feat({TASK_ID}): <título>" --body "Entregue pelo Copilot/VSCode."
   ```
3. Acompanhar CI: `gh pr checks` → corrigir falhas → mergear quando verde:
   ```bash
   gh pr merge --squash --auto
   ```
4. Atualizar `tasks/COPILOT-QUEUE.md` — mover para `✅ Concluídas`.
5. Para tarefas T-ID: mover no `tasks/KANBAN.md` para `## ✅ Done` (manter `Owner: Copilot/VSCode`).

---

## Fase 4 — Handoff

1. Registrar aprendizados em `.agents/progress.txt` (padrões novos, gotchas, localização de arquivos).
2. Atualizar `tasks/COPILOT-QUEUE.md` com o estado ao final da sessão.
3. Não apagar branches entregues antes do merge ser confirmado.

---

## Isolamento — Regras Críticas

| Regra | Detalhe |
|-------|---------|
| ✅ Trabalhar em | `~/production-site-copilot` |
| ✅ Branch base | Sempre `origin/main` atualizado |
| ❌ Nunca commitar em | `main` diretamente |
| ❌ Nunca pegar tasks | Com `Owner: Antigravity` ou sem Owner definido |
| ❌ Nunca modificar | `~/production-site` (Cursor) ou `~/production-site-antigravity` |
| ⚠️  Conflicts em shared files | `KANBAN.md`, `AGENTS.md` → sempre rebase antes de push |
