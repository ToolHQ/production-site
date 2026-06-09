# T-342: SSDNodes CI — bump Sonar 26.6 + Jenkins 2.567 JDK25

- **Status**: Done
- **Priority**: 🔼 High
- **Owner**: Cursor / AI Radar
- **Epic**: T-341 SSDNodes CI Platform
- **Est**: 4h
- **Criado**: 2026-06-05

## Context

O deploy inicial da plataforma CI (T-341) pinou versões **desatualizadas**:

| Componente | Estava no Git | Alvo (canônico) |
|------------|---------------|-----------------|
| SonarQube CE | `10.7.0-community` (chart legado) | `26.6.0.123539-community` (Community Build) |
| Jenkins controller | `2.504.1-jdk17` | `2.567-slim-jdk25` |
| Helm Jenkins | `5.7.10` | `5.9.22` |
| Helm SonarQube | _(sem pin)_ | `2026.3.1` |

Sem o bump, builds verdes não refletem stack atual — impossível avaliar citools/CodeQL/Sonar no caminho certo.

**Migração Sonar 10.x → 26.x:** salto direto não é suportado pelo Sonar (exige 24.12 → 25.12 → 26.x). Se a instância legada falhar após bump, usar fresh install (CI sem histórico):

```bash
bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh sonarqube  # upload manifests
bash oci-k8s-cluster/scripts/ssdnodes/upgrade_sonar_stepwise.sh --fresh       # drop DB+PVC → 26.6
# ou preservar histórico (lento):
bash oci-k8s-cluster/scripts/ssdnodes/upgrade_sonar_stepwise.sh --stepwise
```

**Jenkins JDK25:** controller slim; agents K8s continuam `rust:1.88-bookworm` (build toolchain independente do JDK do controller).

## Tasks

- [x] Criar task T-342 + entrada KANBAN
- [x] Atualizar `sonarqube-values.yaml` (`community.buildNumber` + `image.tag`)
- [x] Atualizar `jenkins-values.yaml` (`2.567-slim-jdk25`)
- [x] Pin helm charts em `deploy_ssdnodes_components.sh` e `setup_jenkins_ci_jobs.sh`
- [x] Commit + push PR #394 (feat/t-341-ssdnodes-ci-platform)
- [x] Deploy live: `deploy_ssdnodes_components.sh ci-platform`
- [x] Smoke: `validate_ssdnodes_ci.sh` + Jenkins build multibranch (2026-06-09 PASS)
- [x] Marcar T-342 done

## Validação

```bash
export KUBECONFIG=~/.kube/ssdnodes.yaml
bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh ci-platform
bash scripts/harness/validate_ssdnodes_ci.sh
# Versões em runtime:
kubectl get sts jenkins -n jenkins -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl get sts sonarqube-sonarqube -n sonarqube -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}' 2>/dev/null || \
  kubectl get deploy -n sonarqube -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].image}{"\n"}{end}'
curl -fsS https://sonar.ssdnodes.dnor.io/api/system/status | jq .
```
