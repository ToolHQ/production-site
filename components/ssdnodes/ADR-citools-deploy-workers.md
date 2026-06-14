# ADR: citools deploy workers (T-344)

**Status:** Proposed  
**Data:** 2026-06-06  
**Relacionado:** T-344, T-346–T-348, T-222 (Hetzner builder), T-341 (Jenkins SSDNodes)

## Contexto

- **Quality CI** — `pipeline.yaml` + Jenkins multibranch (verify, CodeQL, Sonar).
- **Deploy apps** — `apps/*/deploy.sh` + `deploy-buildx.sh` (Hetzner ARM64 → Nexus → kubectl OCI).
- **SSDNodes** — cluster x86 separado; CI roda lá; deploy de apps prod ainda é OCI.

Operador quer **build/deploy pontual via Jenkins** sem abandonar `deploy.sh`.

## Decisão

1. **`deploy-catalog.yaml`** — catálogo declarativo (id, script, worker, target, whenPaths).
2. **citools deploy** — `list | plan | run` — mesmo espírito que quality `pipeline.yaml`.
3. **Workers** — wrappers que preparam env e executam o `deploy.sh` existente:

| Worker | Build | Deploy target |
|--------|-------|---------------|
| `hetzner` | buildx remoto ARM64 | — |
| `ssdnodes-agent` | x86 no agent Jenkins (fase 2) | — |
| — | — | `oci` (kubectl tunnel) |
| — | — | `ssdnodes` (kubeconfig monstro) |

4. **Jenkins job `deploy-apps`** — parametrizado; **separado** do multibranch quality.
5. **`deploy.sh` permanece** — citools não reimplementa build/push/apply.

## Não objetivos (fase 1)

- CD automático on merge main
- Remover `deploy.sh` ou TUI deploy
- Build ARM64 inside Jenkins pod (usa Hetzner SSH)

## Consequências

| + | − |
|---|---|
| Um catálogo descobrível | Manutenção catalog + deploy.sh |
| Jenkins UI para deploy ops | Secrets kubeconfig/SSH no cluster |
| Local `citools deploy run` = Jenkins | Spike buildx-from-agent se necessário |

## Fases

Ver [T-344 epic](../../tasks/2026/Q2/T-344-Program-citools-deploy-CI-closure-epic.md).

## Referências

- [deploy-buildx.sh](../../oci-k8s-cluster/scripts/lib/deploy-buildx.sh)
- [ADR citools harness](ADR-citools-harness-evolution.md)
