# T-202: Codex worktree isolation and autopilot coordination

- **Status**: Done
- **Priority**: 🔼 High
- **Epic/Owner**: Codex / Rust Rover
- **Estimation**: 1h

## Context

O diretório `~/production-site-rust-rover-claude` nasceu como cópia do worktree do Antigravity e apontava para o mesmo gitdir:

`/home/dnorio/production-site/.git/worktrees/production-site-antigravity`

Isso tornava o status Git enganoso e criava risco real de conflito com a frente T-195 do Antigravity. A sessão Codex foi isolada em uma worktree própria, partindo de `origin/main`, e agora precisa de regras versionadas para operar em autopilot sem disputar ownership com Cursor, Copilot/VSCode ou Antigravity.

Autopilot aqui significa reduzir interrupções para comandos rotineiros e manter Codex em uma faixa segura: coordenação, infra/tooling e revisão. O sandbox ainda pode exigir aprovação para rede, GitHub, cluster e escrita fora da worktree; nesses casos, Codex deve pedir aprovações com `prefix_rule` restrita e reutilizável, nunca com comandos amplos.

## Tasks

- [x] Confirmar isolamento de `~/production-site-rust-rover-claude` em branch própria.
- [x] Criar fila `tasks/CODEX-QUEUE.md`.
- [x] Criar workflow `.agents/workflows/codex_loop.md`.
- [x] Ensinar `.agents/scripts/auto_loop.sh` a filtrar `Owner: Codex`.
- [x] Atualizar `AGENTS.md` e `docs/agent-orchestration.md` com Codex no mapa multi-agente.
- [x] Validar dry-run do loop Codex.
- [x] Rodar validação local path-aware dos arquivos alterados.

## Validação

- `git status --short --branch` confirmou worktree limpa em `codex/rust-rover-main` antes da T-202.
- `git rev-list --left-right --count origin/main...HEAD` retornou `0 0` antes da branch da task.
- `bash -n .agents/scripts/auto_loop.sh` passou sem erro.
- `AGENT_OWNER=Codex WORKSPACE_DIR=/home/dnorio/production-site-rust-rover-claude ./.agents/scripts/auto_loop.sh --dry-run` selecionou `T-202` usando `.agents/workflows/codex_loop.md`.
- `./tools/harness/verify.sh verify-changed --paths ...` falhou apenas por caminhos sem gate configurado: `.agents/scripts/auto_loop.sh`, `.agents/workflows/codex_loop.md`, `AGENTS.md`.
- `./tools/harness/verify.sh verify-changed --allow-unmapped --paths ...` passou com `fail=0`; todos os gates de stack foram `SKIP` porque a mudança é de documentação/coordenação.
