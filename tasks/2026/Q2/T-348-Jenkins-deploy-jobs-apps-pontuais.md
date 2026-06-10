# T-348: Jenkins deploy jobs — apps pontuais

- **Status**: Done (MVP — DRY_RUN smoke)
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: [T-344](T-344-Program-citools-deploy-CI-closure-epic.md)
- **Est**: 1w
- **Criado**: 2026-06-06
- **Depende de**: T-346, T-347

## Context

Multibranch `production-site` = **quality CI** (verify, CodeQL, Sonar). Deploy de apps é **manual** via `./deploy.sh` — operador precisa SSH tunnel, Hetzner, etc.

Queremos job Jenkins **parametrizado** para build/deploy pontual de um app, reutilizando citools + workers, sem acoplar deploy ao pipeline de PR.

## Design

### Job: `deploy-apps` (Pipeline job, não multibranch)

Parâmetros Active Choices ou string:

| Param | Valores |
|-------|---------|
| `APP` | lista de `citools deploy list` |
| `TARGET` | `oci` \| `ssdnodes` |
| `DRY_RUN` | boolean |
| `BUILD_WORKER` | `hetzner` (default) \| `ssdnodes-agent` |

### Arquivos

| Arquivo | Função |
|---------|--------|
| `components/ssdnodes/jenkins/pipeline-deploy.yaml` | stages: plan → approve? → run |
| `components/ssdnodes/jenkins/Jenkinsfile.deploy` | loop citools deploy (espelho generic) |
| `components/ssdnodes/jenkins/bootstrap-deploy-job.groovy` | seed job |
| `oci-k8s-cluster/scripts/ssdnodes/seed_jenkins_deploy_job.sh` | idempotente |

### pipeline-deploy.yaml (draft)

```yaml
version: 1
name: deploy-apps
stages:
  - id: deploy-plan
    stageName: Plan deploy
    run: citools deploy plan --app ${APP} --target ${TARGET}

  - id: deploy-run
    stageName: Deploy
    when: env:CITOOLS_DRY_RUN
    run: citools deploy run --app ${APP} --target ${TARGET}

  - id: deploy-verify
    stageName: Rollout verify
    run: ./tools/citools/scripts/deploy-rollout-verify.sh
```

### Segurança

- Job deploy **não** roda em multibranch PR — só `build` manual ou role Jenkins
- Credenciais: kubeconfig, hetzner SSH, registry — K8s secrets
- Audit log: BUILD_URL + APP + TARGET em descrição github-status opcional `jenkins/deploy`

## Tasks

- [x] `pipeline-deploy.yaml` + `Jenkinsfile.deploy`
- [x] `seed_jenkins_deploy_job.sh` + bootstrap groovy
- [x] Integrar em `setup_jenkins_ci_jobs.sh`
- [ ] Jenkins credentials: `kubeconfig-oci`, `hetzner-ssh` (se spike OK)
- [ ] RBAC: restringir job a admin ou grupo (JCasC)
- [x] UI: link doc em job description → T-344
- [x] Smoke: deploy `py-back-end` → OCI via Jenkins UI (DRY_RUN OK live) — build #7 SUCCESS
- [x] Docs `components/ssdnodes/jenkins/README.md` seção Deploy jobs

## Validação

```
https://jenkins.ssdnodes.dnor.io/job/deploy-apps/
Build with Parameters: APP=py-back-end, TARGET=oci, DRY_RUN=true → plan OK
DRY_RUN=false → rollout green
```

## Fora de escopo (fase 2)

- Auto-deploy on merge main (CD)
- Deploy matrix (all changed apps)
- Substituir TUI `deploy.sh` wrapper
