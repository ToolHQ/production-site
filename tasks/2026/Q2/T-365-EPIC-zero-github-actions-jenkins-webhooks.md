# T-365: Épico — Zero GitHub Actions ($0) → Jenkins SSDNodes + webhooks

- **Status**: 🏎️ In Progress
- **Priority**: 🚨 Critical
- **Owner**: Cursor / AI Radar
- **Est.**: 2–3d (fases incrementais)

## Context

GitHub Actions cobra minutos em runners hosted (`ubuntu-latest`, `macos-latest`) e
limita minutos free. O cluster **Jenkins na SSDNodes** (12 vCPU / 60 GB) já substitui
`quality-gates`, CodeQL e docs via **multibranch + webhook** (`jenkins/citools`) no
repo `ToolHQ/production-site` — ver [docs/ci-jenkins-migration.md](../../docs/ci-jenkins-migration.md).

**Gap:** workflows ainda ativos em GHA:

| Repo | Workflow | Custo |
|------|----------|-------|
| `ToolHQ/production-site` | `agent-meter-validation.yml` | self-hosted (Hetzner) — ok, mas duplicado |
| `ToolHQ/production-site` | `release-agent-meter.yml` | **macos-14 hosted** 💸 |
| `ToolHQ/production-site` | `release-agent-meter-proxy.yml` | mixed |
| `ToolHQ/production-site` | `codeql-security.yml` | push main + weekly |
| `dnorio/agent-meter` | `ci.yml` | **ubuntu-latest hosted** 💸 |
| `dnorio/agent-meter` | `release.yml` | **macos + windows hosted** 💸 |

**Objetivo:** todo CI/release vira **Jenkins multibranch** disparado por **webhook
GitHub → `https://jenkins.ssdnodes.dnor.io/github-webhook/`**, publicando **commit
status** (`jenkins/citools`, `jenkins/agent-meter`, etc.) consumível em branch
protection — **$0 variável**.

## Tasks

### Fase 1 — Inventário + aposentadoria GHA (este PR)
- [x] Documentar épico T-365 + mapa de workflows
- [x] Aposentar GHA `ci.yml` / `release.yml` no OSS (`workflow_dispatch` only)
- [x] Aposentar GHA agent-meter/release/codeql no monorepo (`workflow_dispatch` only)
- [x] `Jenkinsfile` no repo OSS + `scripts/ci/*`
- [x] `bootstrap-agent-meter-oss-job.groovy` + seed script
- [x] Estender `configure_github_ci_protection.sh` com `--repo` / `--context`
- [x] Stage `agent-meter-validate` no `pipeline.yaml` (monorepo)

### Fase 2 — Jobs live no Jenkins (operacional)
- [ ] Rodar `seed_jenkins_agent_meter_oss_job.sh` no SSDNodes
- [ ] `configure_github_ci_protection.sh --repo dnorio/agent-meter --context jenkins/agent-meter`
- [ ] Branch protection `main`: exigir `jenkins/agent-meter` (OSS) e `jenkins/citools` (monorepo)
- [ ] Indexar multibranch + validar PR de teste em ambos repos

### Fase 3 — Release sem GHA hosted
- [ ] Job Jenkins `agent-meter-oss-release` (tag `v*`) — Linux x86_64/arm64 na SSDNodes/Hetzner
- [ ] Migrar `release-agent-meter.yml` / proxy release para Jenkins + `gh release upload`
- [ ] macOS release: build local ou runner self-hosted (sem `macos-latest`)

### Fase 4 — Hardening
- [ ] Remover badges GHA do README OSS → badge Jenkins/build
- [ ] Dashboard operacional: falhas webhook, rotação PAT, UFW GitHub hooks
- [ ] Documentar runbook em [docs/ci-zero-github-actions.md](../../docs/ci-zero-github-actions.md)

## Status checks (contrato)

| Repo | Context GitHub | Job Jenkins |
|------|----------------|-------------|
| `ToolHQ/production-site` | `jenkins/citools` | `production-site` multibranch |
| `dnorio/agent-meter` | `jenkins/agent-meter` | `agent-meter-oss` multibranch |

## Referências

- T-341, T-345, T-349 (Jenkins platform + webhook + Blue Ocean)
- [components/ssdnodes/jenkins/README.md](../../components/ssdnodes/jenkins/README.md)
- AMOSS-12 release OSS (binários) — alinhado à Fase 3 deste épico
