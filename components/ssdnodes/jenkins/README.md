# Jenkins CI — production-site (citools)

Orquestrador mínimo para o monorepo. **Stages vivem em `pipeline.yaml`**, não neste diretório Groovy.

## Arquivos

| Arquivo | Função |
|---------|--------|
| [Jenkinsfile.generic](Jenkinsfile.generic) | Pipeline declarativo — checkout + `agent-setup.sh` + `citools run-all` |
| [agent-setup.sh](agent-setup.sh) | Deps do agent (shellcheck, sonar-scanner, build citools) |
| [scripts/verify-branch-ci.sh](scripts/verify-branch-ci.sh) | Harness vs `origin/main` (CI) |
| [pipeline.yaml](pipeline.yaml) | Stages CI (verify-branch, sonar-scan, …) |
| [jcasc-ci-snippet.yaml](jcasc-ci-snippet.yaml) | Referência JCasC (Sonar server URL); credenciais via setup script |

## Setup inicial (uma vez)

```bash
# 1. Credenciais K8s + JCasC
bash oci-k8s-cluster/scripts/ssdnodes/setup_jenkins_ci_jobs.sh --update-home-creds
# 2. Job multibranch
bash oci-k8s-cluster/scripts/ssdnodes/seed_jenkins_ci_job.sh
# 3. Validar
bash scripts/harness/validate_ssdnodes_ci.sh
# UI: https://jenkins.ssdnodes.dnor.io/job/production-site/
```

**Pré-requisitos:** `gh auth login` (repo private), Jenkins/Sonar live, senha Sonar em `~/ssdnodes-ci-platform-credentials.txt`.

## O que o setup cria

1. **Credenciais Jenkins (global)**
   - `sonar-token` — token SonarQube (API `user_tokens/generate`)
   - `github-pat` — PAT do `gh auth token`

2. **SonarQube server** — instalação `SonarQube SSDNodes` → `https://sonar.ssdnodes.dnor.io`

3. **Projeto Sonar** — `production-site` (key = nome)

4. **Multibranch job** `production-site`
   - Fonte: Git `ToolHQ/production-site`
   - Jenkinsfile: `components/ssdnodes/jenkins/Jenkinsfile.generic`
   - Descobre branches via `BranchDiscoveryTrait`

## Variáveis no Jenkinsfile

| Env | Origem | Uso |
|-----|--------|-----|
| `SONAR_TOKEN` | credencial `sonar-token` | stage `sonar-scan` no pipeline.yaml |
| `CITOOLS_PIPELINE` | fixo | path do pipeline.yaml |
| `VALIDATE_SSDNODES_CI` | opcional | habilita smoke remoto no pipeline |

## Adicionar stage

Edite [pipeline.yaml](pipeline.yaml) — **não** o Jenkinsfile:

```yaml
  - id: meu-gate
    run: ./tools/harness/verify.sh verify-changed
```

Teste local:

```bash
cd tools/citools && cargo build --release
citools plan --pipeline components/ssdnodes/jenkins/pipeline.yaml
citools run-all --pipeline components/ssdnodes/jenkins/pipeline.yaml
```

## Troubleshooting

| Sintoma | Ação |
|---------|------|
| `set: Illegal option -o pipefail` | Blocos `sh` precisam `#!/usr/bin/env bash` (dash não suporta pipefail) |
| URL `feat%252Ft-341` | Encoding duplo de `/` no nome da branch — normal no multibranch |
| verify-changed “No changed paths” | CI usa `verify-branch-ci.sh` (diff vs `origin/main`), não working tree |
| Branch indexing 0 branches | Verificar `github-pat`; repo private precisa PAT com `repo` |
| `sonar-scanner` not found | `agent-setup.sh` baixa scanner; sonar-scan skip se sem `sonar-project.properties` |
| Plugin GitSCMSource error | `kubectl logs jenkins-0 -n jenkins -c jenkins` |
| Re-run setup | Idempotente — sobrescreve creds e re-scan job |

## Referências

- [ADR citools](../ADR-citools-harness-evolution.md)
- [tools/citools/README.md](../../../tools/citools/README.md)
- [T-341](../../../tasks/2026/Q2/T-341-SSDNodes-Jenkins-SonarQube-Platform.md)
