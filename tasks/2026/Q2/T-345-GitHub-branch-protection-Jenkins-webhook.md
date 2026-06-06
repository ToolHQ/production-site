# T-345: GitHub branch protection + Jenkins webhook

- **Status**: In Progress
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: [T-344](T-344-Program-citools-deploy-CI-closure-epic.md)
- **Est**: 1d
- **Criado**: 2026-06-06

## Context

CI quality roda no Jenkins e publica status `jenkins/citools`, mas:

- `main` **sem branch protection** (verificado via `gh api`)
- Multibranch depende de **indexação periódica** (PAT) — latência em PRs
- GHA aposentados não bloqueiam merge; sem required check o bypass é trivial

## Research

| Item | Estado atual | Alvo |
|------|--------------|------|
| Commit status context | `jenkins/citools` via `github-status.sh` | ✓ implementado |
| Required check `main` | ausente | `jenkins/citools` |
| Webhook GitHub → Jenkins | T-341-3 opcional | `/github-webhook/` + HMAC |
| Poll SCM | default multibranch | fallback se webhook falhar |

Webhook ingress: `components/ssdnodes/jenkins-github-webhook-ingress.yaml` (draft T-341) com IP allowlist GitHub.

## Tasks

- [ ] Documentar runbook em `docs/ci-jenkins-migration.md` (gh api + UI)
- [ ] Script idempotente `scripts/harness/configure_github_ci_protection.sh`
- [ ] Aplicar branch protection: required check `jenkins/citools`, 1 approval opcional
- [ ] Criar GitHub webhook secret K8s + ingress allowlist (T-341-3)
- [ ] Configurar webhook repo `ToolHQ/production-site` → `https://jenkins.ssdnodes.dnor.io/github-webhook/`
- [ ] Validar: push branch → build automático &lt; 2 min
- [ ] Validar: PR #394 mostra check `jenkins/citools` required
- [ ] Remover checks legados `Quality Gates/*` se ainda listados

## Validação

```bash
gh api repos/ToolHQ/production-site/branches/main/protection
# push test branch → Jenkins build triggered
gh pr checks 394
```
