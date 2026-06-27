# Jenkins CI — production-site (citools)

Orquestrador **genérico**: Groovy só faz `readJSON` + `stage(stageName)`. Negócio em `pipeline.yaml` + `citools`.

## Contrato Jenkins ↔ citools

```
pipeline.yaml
     │
     ▼
citools next --json  ──►  { "done": false, "stageName": "Verify branch", "id": "verify-branch", ... }
     │                              │
     │                              ▼
     │                     readJSON + stage(step.stageName) { citools run id }
     │
     └── (done: true) → fim do loop
```

Preview de todos os stages habilitados: `citools export-json | jq .`

## Stages CI (substituem GitHub Actions)

| Stage | Substitui | Script |
|-------|-----------|--------|
| Verify branch | quality-gates.yml | [verify-branch-ci.sh](scripts/verify-branch-ci.sh) + [ci-prep.sh](scripts/ci-prep.sh) |
| CodeQL | codeql.yml | [codeql-scan.sh](../../../tools/citools/scripts/codeql-scan.sh) |
| Sonar scan | — | [sonar-scan.sh](../../../tools/citools/scripts/sonar-scan.sh) |
| Update CHANGELOG | auto-docs.yml (main) | [changelog-update.sh](../../../tools/citools/scripts/changelog-update.sh) |

Ver [docs/ci-jenkins-migration.md](../../../docs/ci-jenkins-migration.md).

## Arquivos

| Arquivo | Função |
|---------|--------|
| [Jenkinsfile.generic](Jenkinsfile.generic) | Prepare + loop `citools next --json` → stages dinâmicos |
| [pipeline.yaml](pipeline.yaml) | **Fonte de verdade** — id, stageName, when, run |
| [agent-setup.sh](agent-setup.sh) | Deps do agent (shellcheck, sonar-scanner, build citools) |
| [jenkins-prepare.sh](jenkins-prepare.sh) | Fetch autenticado `origin/main` pós-checkout |
| [scripts/verify-branch-ci.sh](scripts/verify-branch-ci.sh) | Harness vs `origin/main` (CI) |
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
    stageName: Meu gate
    when: env:MINHA_FLAG   # opcional — citools filtra em next --json
    run: ./scripts/meu-gate.sh
```

Campos úteis: `stageName` (Blue Ocean), `when: env:VAR`, `jenkins: false` (só local/run-all).

Teste local:

```bash
cd tools/citools && cargo build --release
citools export-json --pipeline components/ssdnodes/jenkins/pipeline.yaml | jq .
citools next --json
citools run-all --pipeline components/ssdnodes/jenkins/pipeline.yaml
```

## Deploy pontual (T-348)

Job **deploy-apps** — Pipeline parametrizado (não multibranch):

| Param | Descrição |
|-------|-----------|
| `APP` | App do `deploy-catalog.yaml` |
| `TARGET` | `oci` \| `ssdnodes` |
| `DRY_RUN` | `true` = só plan; `false` = executa `deploy.sh` via worker wrapper |

```bash
# Seed idempotente
bash oci-k8s-cluster/scripts/ssdnodes/seed_jenkins_deploy_job.sh

# Local
APP=py-back-end TARGET=oci citools deploy plan --app "$APP" --target "$TARGET"
APP=py-back-end TARGET=oci citools deploy run --app "$APP" --target "$TARGET" --dry-run
```

URL: https://jenkins.ssdnodes.dnor.io/job/deploy-apps/

Workers: [T-347](../../../tasks/2026/Q2/T-347-Deploy-workers-Hetzner-OCI-SSDNodes.md) — `deploy-run.sh` + `deploy-target-env.sh`

## Visualização de pipelines (T-349)

Plugins: **Blue Ocean**, **Pipeline Stage View**, **Pipeline Graph View** (`jenkins-values.yaml`).

| UI | URL |
|----|-----|
| Blue Ocean (home) | https://jenkins.ssdnodes.dnor.io/blue/ |
| production-site | https://jenkins.ssdnodes.dnor.io/blue/organizations/jenkins/production-site/activity |
| deploy-apps | https://jenkins.ssdnodes.dnor.io/blue/organizations/jenkins/deploy-apps/activity |
| Stage View (clássico) | Job → aba **Pipeline** (colunas por stage) |

Stages vêm do `stageName` em `pipeline.yaml` / `pipeline-deploy.yaml` (citools `next --json`).

```bash
bash scripts/harness/validate_ssdnodes_ci.sh   # inclui smoke /blue/ + plugins
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
| Reverse proxy broken | `controller.jenkinsUrl` + JCasC `location.url` (T-343); redeploy `jenkins-values.yaml` |
| CSP banner | `javaOpts` DirectoryBrowserSupport.CSP em `jenkins-values.yaml` (T-343) |

## Referências

- [ADR citools](../ADR-citools-harness-evolution.md)
- [tools/citools/README.md](../../../tools/citools/README.md)
- [T-341](../../../tasks/2026/Q2/T-341-SSDNodes-Jenkins-SonarQube-Platform.md)

## Deploy dedicado por app (REF branch/hash)

Jobs dedicados — 1 por app, com seleção de branch/hash e log rotation isolado (50 builds).

| Job | App | URL |
|-----|-----|-----|
| `deploy-rs-observability-api` | rs-observability-api | /job/deploy-rs-observability-api/ |
| `deploy-agent-meter` | agent-meter | /job/deploy-agent-meter/ |
| `deploy-ai-radar` | ai-radar | /job/deploy-ai-radar/ |
| `deploy-gta-vi` | gta-vi | /job/deploy-gta-vi/ |
| `deploy-tor` | tor | /job/deploy-tor/ |
| `deploy-py-back-end` | py-back-end | /job/deploy-py-back-end/ |
| `deploy-back-end` | back-end | /job/deploy-back-end/ |
| `deploy-rs-axum-back-end` | rs-axum-back-end | /job/deploy-rs-axum-back-end/ |

### Parâmetros por job

| Param | Tipo | Default | Descrição |
|-------|------|---------|-----------|
| `APP` | string | (definido pelo job) | App do deploy-catalog.yaml |
| `REF` | string | `main` | Branch (`main`, `feat/foo`) ou commit hash (`abc1234f`) |
| `TARGET` | choice | `oci` | `oci` ou `ssdnodes` |
| `DRY_RUN` | boolean | `true` | `true` = plan only, `false` = executa deploy |

### Build description

Cada build mostra automaticamente: `REF=main | SHA=abc1234f | Author: Name "commit message"`

### Setup

```bash
bash oci-k8s-cluster/scripts/ssdnodes/seed_jenkins_deploy_ref_jobs.sh
```

### Fluxo

1. Jenkins carrega `Jenkinsfile.deploy-ref` da branch `main`
2. Pipeline faz checkout do `REF` especificado (branch ou hash)
3. Set build description com REF + SHA + autor + mensagem
4. Executa `citools deploy plan` → (se DRY_RUN=false) `citools deploy run`
