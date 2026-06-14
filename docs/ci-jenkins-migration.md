# CI no Jenkins SSDNodes (migração GHA)

GitHub Actions **quality-gates**, **codeql** e **auto-docs** foram aposentados (`workflow_dispatch` apenas — não rodam em push/PR).

CI primário: **Jenkins multibranch** `production-site` + **citools** + **harness**.

URL: https://jenkins.ssdnodes.dnor.io/job/production-site/

## Sim — multibranch substitui os GHA de quality

O job **`production-site`** descobre branches/PRs do repo e executa `Jenkinsfile.generic`, que lê stages de `pipeline.yaml` via `citools next --json`.

| GitHub Actions (aposentado) | Jenkins stage | Script |
|-----------------------------|---------------|--------|
| `quality-gates.yml` — shell/rust/bats/js/yaml | **Verify branch** | `verify-branch-ci.sh` → `tools/harness/verify.sh` |
| `codeql.yml` — JS + Python SARIF | **CodeQL** | `tools/citools/scripts/codeql-scan.sh` |
| _(Sonar no GHA nunca existiu)_ | **Sonar scan** | `tools/citools/scripts/sonar-scan.sh` |
| `auto-docs.yml` — git-cliff na main | **Update CHANGELOG** | `changelog-update.sh` (`when: branch:main`) |

Stages path-aware (`whenPaths`) pulam CodeQL/Sonar quando o diff não toca paths relevantes.

## Status no GitHub (PR / branch protection)

Cada build publica commit status **`jenkins/citools`** via `github-status.sh` (pending → success/failure).

**Gap atual:** branch protection em `main` **não** exige `jenkins/citools` ainda — configurar no GitHub:

```
Settings → Branches → main → Require status checks → jenkins/citools
```

Remover checks legados `Quality Gates / *` quando Jenkins estiver verde nos PRs.

## Disparo de builds

| Evento | Como dispara hoje |
|--------|-------------------|
| Push branch | Indexação multibranch (GitHub PAT) — re-scan periódico |
| PR aberto/atualizado | Mesmo job multibranch na branch do PR |
| Manual | Build Now no Jenkins |

Webhook GitHub → Jenkins (T-341-3) ainda opcional; poll/indexação cobre MVP.

## Local (paridade com CI)

```bash
cd tools/citools && cargo build --release
citools run-all --pipeline components/ssdnodes/jenkins/pipeline.yaml
bash scripts/harness/validate_ssdnodes_ci.sh
```

## Próximo backlog (T-344)

| Fase | ID | Entrega |
|------|-----|---------|
| 1 | T-345 | Branch protection + webhook |
| 2 | T-346 | `deploy-catalog.yaml` + CLI |
| 3 | T-347 | Workers Hetzner/OCI/SSDNodes |
| 4 | T-348 | Jenkins `deploy-apps` job |

Ver [tasks/CITOOLS-DEPLOY-BACKLOG.md](../../tasks/CITOOLS-DEPLOY-BACKLOG.md).

## O que NÃO migrou para Jenkins

| Workflow GHA | Motivo |
|--------------|--------|
| Deploy apps (Hetzner/OCI) | Continua `deploy.sh` + Hetzner builder — fora do escopo CI gates |
| Dependabot / security alerts | GitHub nativo |
| Outros workflows com `push`/`pull_request` | Ver `.github/workflows/` — só os 3 acima foram aposentados |

## Custo

Zero billing GitHub Actions hosted — execução no pod K8s SSDNodes (self-hosted).
