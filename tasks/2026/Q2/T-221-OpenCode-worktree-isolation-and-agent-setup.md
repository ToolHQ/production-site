# T-221: OpenCode agent isolation — worktree, OPENCODE-QUEUE, OpenCode owners

## Objetivo

Adicionar o agente **OpenCode** à orquestração multi-agente do repositório, seguindo o mesmo padrão de Cursor (T-194), Copilot e Codex (T-202).

## Checklist

- [x] Criar worktree `~/production-site-opencode` a partir de `origin/main`
- [x] Criar branch `feat/opencode-agent`
- [x] Criar `tasks/OPENCODE-QUEUE.md`
- [ ] Registrar OpenCode no `AGENTS.md` (tabela de worktrees, regras de convivência)
- [ ] Registrar OpenCode no `tasks/KANBAN.md` (owner reconhecido)
- [ ] Abrir PR com as alterações nos arquivos compartilhados
- [ ] Merge do PR na `main`

## Validação

- [x] `git worktree list` mostra `~/production-site-opencode`
- [x] `tasks/OPENCODE-QUEUE.md` existe e segue o padrão das demais filas
- [ ] `AGENTS.md` lista OpenCode na tabela de worktrees
- [ ] `KANBAN.md` reconhece OpenCode como owner válido
