---
description: Codex Loop — Rust Rover, owner de coordenação/infra/tooling, isolado de Cursor, Copilot e Antigravity.
---

# Codex Loop

## Escopo

Codex opera em `~/production-site-rust-rover-claude` e usa o owner `Codex / Rust Rover`.

Prioridades naturais:

1. Coordenação multi-agente e higiene de worktrees.
2. Infra / Ops de baixo risco, com leitura antes de qualquer ação.
3. DevExp / Tooling e quality gates que não toquem frentes ativas de produto.
4. Revisão, integração e diagnóstico.

## Fora de Escopo Sem Handoff

- `apps/ai-radar/` e tasks `Cursor / AI Radar`.
- `apps/rs-observability-api/web-v2/` durante frente Cluster Pulse do Antigravity.
- Tasks `Copilot/VSCode`, salvo desbloqueio explícito.
- Worktrees de outros agentes.
- Ações destrutivas no cluster, stateful workloads, PVCs, Longhorn, Postgres e Nexus sem confirmação explícita.

## Autopilot

Autopilot significa executar o máximo possível sem interromper o usuário para decisões pequenas.

Ainda assim, o sandbox pode exigir aprovação para:

- Escritas fora de `~/production-site-rust-rover-claude`.
- Rede, `git fetch/push`, `gh`, deploys e comandos que toquem cluster.
- Comandos destrutivos.

Quando houver bloqueio do sandbox, Codex deve pedir aprovação com `prefix_rule` restrita e reutilizável, por exemplo:

- `["git", "-C", "/home/dnorio/production-site-rust-rover-claude", "fetch"]`
- `["git", "-C", "/home/dnorio/production-site-rust-rover-claude", "push"]`
- `["gh", "pr"]`
- `["kubectl"]`, somente após carregar `connect-to-cluster`.

Não pedir prefixo amplo como `bash`, `python`, `rm`, `sudo` ou comandos arbitrários.

## Loop

```bash
cd ~/production-site-rust-rover-claude
AGENT_OWNER='Codex' WORKFLOW_FILE="$PWD/.agents/workflows/codex_loop.md" ./.agents/scripts/auto_loop.sh --dry-run
```

Em execução real, usar um CLI explicitamente configurado em `AI_CLI_COMMAND`. O dry-run deve ser validado antes de qualquer loop real.

## Entrega

- Criar branch a partir de `main` para cada T-ID.
- Atualizar `tasks/KANBAN.md`, `tasks/CODEX-QUEUE.md` e o arquivo da task.
- Rodar validação local quando disponível.
- Abrir PR, acompanhar CI e resolver falhas quando a entrega for publicável.
