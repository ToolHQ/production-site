# 📋 Copilot/VSCode Queue

> **Fila de trabalho exclusiva do GitHub Copilot (VSCode).**
> O `KANBAN.md` continua como **única fonte de verdade** para tarefas T-ID.
> Este arquivo funciona como _sprint board_ de sessão do Copilot — não duplica, apenas filtra e complementa.

## Regras de Uso

- **Copilot** só trabalha em tarefas onde `Owner` contém `Copilot/VSCode` no `KANBAN.md`, ou em micro-tasks listadas aqui.
- **Cursor / Antigravity** não devem pegar tarefas com `Owner: Copilot/VSCode`.
- Micro-tasks (< 30 min, sem branch) ficam apenas aqui. Ao completar, marcam como `[x]` — sem mover para KANBAN.
- Tarefas T-ID exigem branch em `production-site-copilot` → PR → merge.

## 🏎️ Em Andamento (sessão atual)

| ID / Ref                        | Tarefa                                          | Tipo     |
| :------------------------------ | :---------------------------------------------- | :------- |
| `feat/copilot-task-structure`   | Setup isolamento Copilot + queue + loop workflow | Meta/Ops |

## 📋 Próximas (Copilot/VSCode)

> Populado manualmente pelo usuário ou pelo Copilot ao planejar a sessão.
> Referenciar T-IDs do KANBAN.md (com `Owner: Copilot/VSCode`) ou micro-tasks.

| ID / Ref | Tarefa | Prioridade |
| :------- | :----- | :--------- |
| —        | —      | —          |

## 🔬 Micro-Tasks (sem T-ID, sem PR)

> Itens rápidos de uma sessão. Ao concluir, marcar `[x]` aqui e commitá-los na branch corrente (se houver).

- [ ] —

## ✅ Concluídas (histórico recente)

| ID / Ref                      | Tarefa                                               | Data       |
| :---------------------------- | :--------------------------------------------------- | :--------- |
| `feat/copilot-task-structure` | Setup inicial: worktree + queue + loop workflow + PR | 2026-05-16 |
