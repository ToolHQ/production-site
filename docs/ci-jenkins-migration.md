# CI no Jenkins SSDNodes (migração GHA)

GitHub Actions **quality-gates**, **codeql** e **auto-docs** foram aposentados (`workflow_dispatch` apenas).

CI primário: **Jenkins multibranch** + **citools** + **harness**.

## Onde roda

| Antes (GHA) | Agora (Jenkins) |
|-------------|-----------------|
| Detect changed paths + shell/rust/bats/js/yaml | Stage `verify-branch` → `verify-branch-ci.sh` + `tools/harness/verify.sh` |
| CodeQL JS + Python | Stage `codeql` → `tools/citools/scripts/codeql-scan.sh` |
| Sonar (futuro GHA) | Stage `sonar-scan` |
| CHANGELOG git-cliff (main) | Stage `changelog` (when `branch:main`) |

URL: https://jenkins.ssdnodes.dnor.io/job/production-site/

## Pipeline declarativo

Editar [`components/ssdnodes/jenkins/pipeline.yaml`](../components/ssdnodes/jenkins/pipeline.yaml) — **não** duplicar lógica no Jenkinsfile.

## Branch protection (GitHub)

Adicionar required check: **`jenkins/citools`** (commit status enviado pelo Jenkins em cada build).

Remover checks legados `Quality Gates / *` após validar o status no PR.

## Local (paridade com CI)

```bash
cd tools/citools && cargo build --release
citools run-all --pipeline components/ssdnodes/jenkins/pipeline.yaml
```

## Custo

Zero billing GitHub Actions hosted — execução no pod K8s SSDNodes (self-hosted).
