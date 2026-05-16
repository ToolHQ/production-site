# Git worktrees — trabalho paralelo sem pisar o mesmo checkout

Este repo costuma ter **várias frentes ao mesmo tempo** (AI Radar empilhado, hotfix de infra, agentes/Copilot, estabilidade). Usar **`git worktree`** mantém cada branch num diretório físico separado: menos conflitos de `stash`, `checkout` acidental em `main`, e merges/rebases mais claros.

## Convenção de pastas (exemplo em `$HOME`)

| Pasta                      | Branch típica              | Uso                                      |
| -------------------------- | -------------------------- | ---------------------------------------- |
| `production-site-ops`      | `main`                     | Sync, merge, inspecionar histórico limpo |
| `production-site-cursor`   | `feat/cursor-*`, `feat/T-19*` | **Cursor** — AI Radar + deploy cluster |
| `production-site-copilot`  | `feat/copilot-*`           | **Copilot/VSCode** — fila `COPILOT-QUEUE.md` |
| `production-site-antigravity` | `feat/agent-loop`       | **Antigravity** — loop headless          |
| `production-site-infra`    | `fix/postgres-…`, ops      | Manifests/cluster sem misturar app       |

> Ver [agent-orchestration.md](agent-orchestration.md) para KANBAN vs filas por agente.

Ajusta os nomes ao teu disco; o importante é **uma linha de trabalho por árvore**.

## Regras rápidas

1. **Não** fazer `git checkout main` no mesmo diretório onde estás numa feature longa — usa o worktree que já está em `main`.
2. Cada agente/sessão Copilot pode usar **outro path** noutro worktree na **sua** branch.
3. Antes de `git worktree remove`, faz **merge ou abandona** a branch conforme o fluxo normal.

## Comandos

Listar worktrees (o repositório é sempre o mesmo `.git`):

```bash
git worktree list
```

Adicionar um worktree para uma branch que **já existe** no remoto:

```bash
cd ~/production-site-ops   # ou qualquer checkout deste repo
git fetch origin
git worktree add ../production-site-ai-radar feat/T-174-ai-radar-k8s-baseline
```

Criar branch **nova** a partir de `main` noutra pasta:

```bash
git fetch origin
git worktree add -b feat/minha-feature ../production-site-minha-feature origin/main
```

Remover quando o PR fechar:

```bash
git worktree remove ../production-site-ai-radar
git branch -d feat/T-174-ai-radar-k8s-baseline   # após merge, se aplicável
```

## Referência

- Documentação oficial: `git help worktree`
