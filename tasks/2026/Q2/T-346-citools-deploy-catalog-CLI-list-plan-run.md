# T-346: citools deploy catalog + CLI list plan run

- **Status**: 📋 Backlog
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: [T-344](T-344-Program-citools-deploy-CI-closure-epic.md)
- **Est**: 1w
- **Criado**: 2026-06-06

## Context

Cada app tem `deploy.sh` (build Hetzner + kubectl OCI). Não há descoberta central nem plano dry-run. citools quality já usa `pipeline.yaml`; deploy segue o **mesmo padrão** com `deploy-catalog.yaml`.

**Não substituir deploy.sh** — citools resolve app → env → exec script.

## Design

### Arquivo `tools/citools/deploy-catalog.yaml`

```yaml
version: 1
defaults:
  build:
    worker: hetzner
    platform: linux/arm64
  deploy:
    target: oci
    kubeconfig_env: KUBECONFIG_OCI

apps:
  - id: py-back-end
    path: apps/py-back-end
    script: ./apps/py-back-end/deploy.sh
    whenPaths: apps/py-back-end/**

  - id: rs-observability-api
    path: apps/rs-observability-api
    script: ./apps/rs-observability-api/deploy.sh
    build:
      worker: hetzner
    deploy:
      target: oci
    whenPaths: apps/rs-observability-api/**,apps/rs-observability-api/web-v2/**
```

### CLI (Rust)

| Comando | Comportamento |
|---------|---------------|
| `citools deploy list` | IDs + worker + target |
| `citools deploy plan --app ID [--target oci\|ssdnodes]` | JSON: steps build/push/apply, env, script |
| `citools deploy run --app ID [--target T] [--dry-run]` | Executa script com env worker |
| `citools deploy run --changed` | Apps cujo `whenPaths` ∩ diff vs main |

Reutilizar parser `whenPaths` de `paths.rs` (quality pipeline).

## Tasks

- [ ] ADR [ADR-citools-deploy-workers.md](../../components/ssdnodes/ADR-citools-deploy-workers.md) review
- [ ] Schema `deploy-catalog.yaml` + exemplo com 8 apps `apps/*/deploy.sh`
- [ ] Rust: módulo `deploy/` (catalog, plan, run)
- [ ] `citools deploy list|plan|run` + testes unitários catalog parse
- [ ] `whenPaths` + `--changed` integrado ao diff base
- [ ] Docs `tools/citools/README.md` seção Deploy
- [ ] Harness `scripts/harness/validate_citools_deploy_plan.sh` (plan all apps dry)

## Validação

```bash
citools deploy list
citools deploy plan --app py-back-end | jq .
citools deploy run --app py-back-end --dry-run
```
