# ADR: Runner CodeQL vs Fleet Copilot (Ollama) no mesmo host

- **Status**: Aceito (opção C com mitigações)
- **Data**: 2026-05-30
- **Task**: T-320c

## Contexto

`ssdnodes-6a12f10c9ef11` (SSDNodes @ 104.225.218.78) roda simultaneamente:

- Cluster K8s (MinIO 500 GiB, ingress, Dashboard, Kubecost)
- GitHub Actions runner `ssdnodes` (CodeQL x86_64)
- Planejado: Ollama + fleet-ops-gateway (Fleet Copilot)

CodeQL executa código de PRs no mesmo kernel que dados sensíveis.

## Opções consideradas

| Opção | Decisão |
|-------|---------|
| A — Mover runner off-box | Ideal longo prazo; adiar (custo/outro host) |
| B — Runner em VM dedicada | Complexidade alta |
| **C — Aceitar colocation + mitigações** | **Aceito para MVP** |
| D — Pausar CodeQL self-hosted | Perde diagnóstico local |

## Decisão

**Opção C** para o MVP Fleet Copilot, com mitigações obrigatórias:

1. **T-320a** — SSH key-only + fail2ban
2. **T-321** — Ollama `127.0.0.1` only; gateway read-only; RBAC `view`
3. **T-322** — Auth + rate limit no proxy reports
4. **Runner** — workflows limitados a `codeql.yml`; sem secrets de cluster no env do runner
5. **Revisão em 90 dias** — mover CodeQL para Hetzner x86 ou runner dedicado se Fleet Copilot for prod-critical

## Consequências

- Blast radius permanece elevado vs host dedicado só para AI
- Pentest T-324 obrigatório antes de Hermes
- Monitorar `github-runner` disk e process list após deploy Ollama

## Revisão

Reavaliar quando T-321+323 estiverem em produção ≥ 30 dias.
