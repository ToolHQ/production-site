# ADR: Jenkins + SonarQube CE no cluster SSDNodes (T-341)

- **Status**: Aceito
- **Data**: 2026-06-04
- **Task**: [T-341](../../tasks/2026/Q2/T-341-SSDNodes-Jenkins-SonarQube-Platform.md)

## Contexto

O monorepo `production-site` usa CI distribuído:

| Papel | Onde hoje |
|-------|-----------|
| Build ARM64 prod | Hetzner `hetzner-builder` → Nexus OCI |
| Quality gates leves | `tools/harness/verify-changed` + GitHub Actions |
| CodeQL x86 | Runner self-hosted `ssdnodes` no **host** SSDNodes |
| Deploy apps OCI | `apps/*/deploy.sh` |

O cluster K8s no SSDNodes (`ssdnodes-6a12f10c9ef11`, 12 vCPU / 60 GiB) já hospeda MinIO, Dashboard, Kubecost e Fleet Copilot com padrão `*.ssdnodes.dnor.io` + UFW hardened.

[T-141](../../tasks/2026/Q2/T-141-Repo-Quality-Harness-and-Delivery-Gates-Program.md) excluiu **SonarQube SaaS/pesado** na fase harness MVP. Este ADR **reabre escopo** apenas para **SonarQube Community Edition self-hosted** (zero custo variável), como complemento ao harness — não substituto de `cargo clippy` / `eslint`.

## Decisão

Implantar no **K8s SSDNodes** (não OCI):

1. **SonarQube CE** + PostgreSQL dedicado (ClusterIP)
2. **Jenkins LTS** com agents Kubernetes in-cluster (x86)
3. Domínios: `sonar.ssdnodes.dnor.io`, `jenkins.ssdnodes.dnor.io`
4. IaC em `components/ssdnodes/` + deploy via `deploy_ssdnodes_components.sh` + TUI

**Zero custo variável:** apenas Helm charts open source, PVC `local-path`, Let's Encrypt HTTP-01 (já provisionado). Sem SonarCloud, sem Jenkins Cloud, sem DB gerenciado.

## Relação com ADR T-320c (CodeQL colocation)

| Risco | Mitigação T-341 |
|-------|-----------------|
| Blast radius (código de PR no mesmo host) | Namespaces isolados; PSA `restricted` onde possível; Jenkins agents sem secrets OCI |
| RAM pressure | requests/limits; `containerCap: 2`; monitor Kubecost |
| Runner GHA + Jenkins overlap | Jenkins orquestra pipelines locais; GHA mantém CodeQL até migração opcional (T-341-5) |

Revisão em **90 dias**: se RAM > 85% sustained, priorizar mover CodeQL runner para Hetzner (opção A do T-320c).

## Segurança

- Exposição HTTPS via UFW existente (ADMIN + INGRESS + Tailscale)
- Jenkins: signup off, JCasC, agent listener **ClusterIP** (sem NodePort 50000)
- Sonar: `sonar.forceAuthentication=true`; tokens CI em Secret K8s
- NetworkPolicy mínima entre `jenkins`, `sonarqube`, `sonarqube-db`
- Webhooks GitHub: fase 2 com IP allowlist; MVP = poll SCM

## Consequências

- +~6–8 GiB RAM steady no SSDNodes
- Novo playbook operacional na TUI (Hardening 15–17)
- `deploy_components.sh` OCI **bloqueia** componente `ssdnodes` (guardrail)
- DNS manual: registros A para `sonar` e `jenkins` → `104.225.218.78`

## Alternativas rejeitadas

| Alternativa | Motivo |
|-------------|--------|
| SonarCloud / Jenkins Cloud | Custo variável — viola política do repo |
| OCI Ampere | 1 vCPU/6 GiB — inviável para JVM |
| Apenas GHA | Sem UI unificada de quality history; SSD já tem runner x86 |
| Sonar embedded H2 | Não suportado para produção |
