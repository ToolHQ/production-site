# CI $0 — Jenkins SSDNodes em vez de GitHub Actions

> Épico **T-365**. CI primário = **Jenkins na SSDNodes** + webhook GitHub.
> GitHub Actions ficam **`workflow_dispatch` only** (emergência manual, zero minutos).

## Arquitetura

```text
GitHub push/PR/tag
       │
       ▼
https://jenkins.ssdnodes.dnor.io/github-webhook/
       │
       ├── production-site (multibranch) → Jenkinsfile.generic → citools pipeline.yaml
       │      status: jenkins/citools
       │
       └── agent-meter-oss (multibranch) → Jenkinsfile (repo dnorio/agent-meter)
              status: jenkins/agent-meter
```

## Configurar webhook + branch protection

```bash
# Monorepo (já usado em T-345)
bash scripts/harness/configure_github_ci_protection.sh \
  --repo ToolHQ/production-site \
  --context jenkins/citools

# Repo OSS standalone
bash scripts/harness/configure_github_ci_protection.sh \
  --repo dnorio/agent-meter \
  --context jenkins/agent-meter
```

Requer `gh auth login` com permissão admin no repo.

## Seed jobs Jenkins

```bash
# production-site (existente)
bash oci-k8s-cluster/scripts/ssdnodes/seed_jenkins_ci_job.sh

# agent-meter OSS
bash oci-k8s-cluster/scripts/ssdnodes/seed_jenkins_agent_meter_oss_job.sh
```

URLs:

- https://jenkins.ssdnodes.dnor.io/job/production-site/
- https://jenkins.ssdnodes.dnor.io/job/agent-meter-oss/

## Paridade local

```bash
# Monorepo
cd tools/citools && cargo build --release
citools run-all --pipeline components/ssdnodes/jenkins/pipeline.yaml

# OSS (na raiz do clone dnorio/agent-meter)
cargo fmt --all -- --check
cargo clippy --workspace --all-targets
cargo test -p agent-meter-collector -p agent-meter-db
bash scripts/ci/smoke-demo.sh
```

## Workflows GHA aposentados

| Arquivo | Antes | Depois |
|---------|-------|--------|
| `.github/workflows/ci.yml` (OSS) | push/PR | `workflow_dispatch` |
| `.github/workflows/release.yml` (OSS) | tag `v*` | `workflow_dispatch` |
| `agent-meter-validation.yml` | push/PR paths | `workflow_dispatch` |
| `release-agent-meter.yml` | tag | `workflow_dispatch` |
| `release-agent-meter-proxy.yml` | tag | `workflow_dispatch` |
| `codeql-security.yml` | push main + cron | cron weekly only (migrar p/ Jenkins) |

## Custo

- **Jenkins SSDNodes:** infra já provisionada (T-341) — $0 marginal
- **Hetzner self-hosted runner:** $0 (labels `hetzner-ci`) — ok manter opcional
- **Evitar:** `runs-on: ubuntu-latest`, `macos-latest`, `windows-latest` em push/PR/tag
