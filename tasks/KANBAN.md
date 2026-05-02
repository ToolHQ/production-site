# 📋 OCI Cluster Project Board

**System Status**: 🟢 Operacional — Coroot 1.18.6 / Nexus 3.91.1-alpine / Longhorn v1.11.1 live; todos os volumes healthy; longhorn-quota 3cpu/20cpu/24Gi (headroom ok); coroot+clickhouse pinados em node-1/node-3; engine image v1.11.1 deploying (upgrade gradual de volumes) | **Next Milestone**: Observability & Resilience (Q2 2026)

> **Incident 2026-04-03**: Longhorn instance-manager on node-1 was in `error` for 132 days
> (CPU starvation). postgres, nexus, coroot-clickhouse stuck for 19 days. Fixed in commit `7f6b920`.
> Volumes rebuilding replicas. See T-102/T-103/T-104 for follow-up hardening.

## 🏎️ In Progress

| ID  | Task Name | Priority | Owner | Est. |
| :-: | :-------- | :------: | :---: | :--: |


## 🔥 Blocker (Deploy back-end travado)

| ID  | Task Name | Priority | Epic | Est. |
| :-: | :-------- | :------: | :--- | :--: |


## 📅 Backlog (To Do)

| ID  | Task Name | Priority | Epic | Est. |
| :-: | :-------- | :------: | :--- | :--: |

| T-192 | **MinIO PVC Expansion 12→20G** — capacidade: node-1 tem 17G livre, réplica única (1:1); expansão preventiva recomendada para quando chegar a 85%+; daily Longhorn backups podem atingir 85% em ~2 semanas (coroot-prometheus cresce 1.2GiB/backup). _Não urgente — MinIO em 71% com 3.4G livre após T-191/T-194._ | 🔽 Low | Infra / Storage | 2h |
| [T-162](2026/Q2/T-162-AI-Radar-GitHub-Collector.md) | **AI Radar — GitHub Collector** _(releases + metadados de repo, rate-limit aware, GITHUB_TOKEN opcional)_ | 🔽 Low | AI Radar / DevExp | 1d |
| [T-163](2026/Q2/T-163-AI-Radar-Webpage-Fetcher.md) | **AI Radar — Webpage Fetcher** _(URL manual, HTML cleaner, size cap 1MB)_ | 🔽 Low | AI Radar / DevExp | 4h |
| [T-164](2026/Q2/T-164-AI-Radar-LLM-Provider-Abstraction.md) | **AI Radar — LLM Provider Abstraction** _(trait LlmProvider + OpenRouter + Mock; deterministic-only quando LLM_ENABLED=false)_ | 🔽 Low | AI Radar / DevExp | 4h |
| [T-165](2026/Q2/T-165-AI-Radar-Extractor-Pipeline.md) | **AI Radar — Extractor Pipeline** _(prompt v1, raw → extracted, fallback JSON, retry corretivo)_ | 🔽 Low | AI Radar / DevExp | 1d |
| [T-166](2026/Q2/T-166-AI-Radar-Scorer-Deterministico.md) | **AI Radar — Scorer Determinístico** _(regras versionadas v1, decisão por threshold, reasons explicáveis)_ | 🔽 Low | AI Radar / DevExp | 1d |
| [T-167](2026/Q2/T-167-AI-Radar-Scorer-com-LLM-Opcional.md) | **AI Radar — Scorer com LLM Opcional** _(MergePolicy 70/30 deterministic+LLM, ambos persistidos para auditoria)_ | 🔽 Low | AI Radar / DevExp | 4h |
| [T-168](2026/Q2/T-168-AI-Radar-Comparator.md) | **AI Radar — Comparator** _(matriz por categoria, Markdown comparativo, persistência)_ | 🔽 Low | AI Radar / DevExp | 4h |
| [T-169](2026/Q2/T-169-AI-Radar-Digest-Generator.md) | **AI Radar — Digest Generator** _(Markdown daily/weekly, agrupado por decisão, API + CLI)_ | 🔽 Low | AI Radar / DevExp | 1d |
| [T-170](2026/Q2/T-170-AI-Radar-Feedback-Loop.md) | **AI Radar — Feedback Loop** _(POST feedback, relatório de divergência humano vs sistema)_ | 🔽 Low | AI Radar / DevExp | 4h |
| [T-172](2026/Q2/T-172-AI-Radar-Observabilidade.md) | **AI Radar — Observabilidade** _(logs JSON com job_id, /metrics Prometheus, custo LLM, hooks OTEL/Langfuse)_ | 🔽 Low | AI Radar / DevExp / Observability | 4h |
| [T-173](2026/Q2/T-173-AI-Radar-Hardening.md) | **AI Radar — Hardening** _(retry/backoff, limits, idempotência reforçada, reprocess versionado, chaos tests)_ | 🔽 Low | AI Radar / DevExp | 1d |

## ✅ Done

|                                       ID                                        | Task Name                                                                                                                                                  |  Priority   |         Owner         |  Est.  |
| :-----------------------------------------------------------------------------: | :--------------------------------------------------------------------------------------------------------------------------------------------------------- | :---------: | :-------------------: | :----: |
| [T-171](2026/Q2/T-171-AI-Radar-Kubernetes-Operacao-Leve.md) | **AI Radar — K8s onda 2 (CronJob collect + validação)** _(CronJob `ai-radar-collect`, dual-image deploy, Dockerfile.cli migrations fix PR #67, kubeconform CI + `just k8s-validate`; CronJobs extract/score/digest ficam para **T-165/T-166/T-169**)_ | 🔽 Low | AI Radar / DevExp / Infra | 1d |
| [T-161](2026/Q2/T-161-AI-Radar-RSS-Collector.md) | **AI Radar — RSS Collector** _(feed-rs, dedup por content_hash, isolamento de erro por fonte, CLI collect)_ | 🔽 Low | AI Radar / DevExp | 1d |
| T-200 | **Longhorn-quota CPU Headroom + Coroot/ClickHouse Node Pinning** _(requests.cpu 1→3 (era 92% saturado); coroot pinado em k8s-node-1 + clickhouse pinado em k8s-node-3 via nodeSelector; elimina race condition FailedMount (T-195); PR #64)_ | 🔼 High | Infra / Stability | 1h |
| T-199 | **Component Upgrades: Coroot 1.18.6 + Nexus 3.91.1-alpine + Longhorn v1.11.1** _(Coroot 1.18.6 via helm values tag override; Nexus 3.91.1-alpine live 200; Longhorn v1.11.1 rolling upgrade — longhorn-quota bumped 8→20cpu/12→24Gi para suportar novo longhorn-csi-plugin DaemonSet; engine image v1.11.1 deploying; PR #62)_ | 🔼 High | Infra / Upgrade | 4h |
| T-198 | **Longhorn Instance-Manager Rollout Controlado** _(LimitRange 500m/512Mi aplicado; instance-managers reciclados; PR #60)_ | 🔼 High | Infra / Storage | 1h |
| [T-174](2026/Q2/T-174-AI-Radar-Kubernetes-Baseline-Primeiro-Deploy.md) | **AI Radar — K8s baseline (primeiro deploy API)** _(namespace `ai-radar`, Deployment+Service+Secret `DATABASE_URL`, Kustomize+Nexus ARM64, probes `/health`, smoke `/sources`; merge **PR #54**)_ | 🔽 Low | AI Radar / DevExp / Infra | 4h |
| T-194 | **Nexus npm-proxy Cleanup + Compact blob store** _(402 componentes npm-proxy deletados via REST API; compact task criada via ExtDirect API; 3 rounds de compact executados; nexus/content 4.5GiB→2.5GiB; MinIO 99%→71%; 3.4GiB livres)_ | 🔼 High | Infra / Storage | 2h |
| T-196 | **Coroot OOM fix + Nexus JVM overcommit fix** _(coroot limits 600→900Mi + requests 50→100Mi; Nexus MaxDirectMemorySize capped 2703m→512m evitando OOMKill; ambos aplicados live + versionados em IaC; PR #57)_ | 🔼 High | Infra / Reliability | 1h |
| T-191 | **MinIO Backup Retention Audit & Cleanup** _(fase 1: 18 backups postgres-0 + 2 etcd + .trash = 1.3GiB liberados 92%→87%; fase 2: ver T-194; backup Error coroot-prometheus cc2747a5 deletado; total MinIO: 99%→71%)_ | 🔼 High | Infra / Storage | 3h |
| T-193 | **DiskPressure Master + kube-controller-manager CrashLoop — Incidente 2026-05-01** _(18G de réplicas órfãs deletadas do master; disco 97%→49%; kube-controller-manager limits 128Mi→256Mi / 300m→500m; todos os pods Running; `static-pod-resources.yaml` atualizado e commitado)_ | 🚨 Critical | Infra / Control-Plane | 2h |
| [T-190](2026/Q2/T-190-Longhorn-Instance-Manager-Flapping-and-Nexus-Containment.md) | **Longhorn Flapping + Nexus Containment** _(todos os volumes healthy; nexus pin node-2; minio TLS corrigido; ingress hostPort 5432 removido; postgres-1 restaurado em node-1)_ | 🚨 Critical | Infra / Storage | 1d |
| [T-158](2026/Q2/T-158-Stateful-Placement-and-HostPort-Conflict-Remediation.md) | **Stateful Placement and HostPort Conflict Remediation** _(hostPort 5432 removido do ingress-nginx; postgres-1 `1/1 Running` no node-1; volume healthy)_ | 🚨 Critical | Infra / Platform | 1d |
| [T-160](2026/Q2/T-160-AI-Radar-Banco-e-Modelo-de-Dados.md) | **AI Radar — Banco e Modelo de Dados** _(schema `ai_radar` no Postgres compartilhado: 6 tabelas, 22 índices, FKs CASCADE, idempotência via UNIQUE `(source_id,content_hash)`; pool SQLx com `RepoError` tipado; 6 traits + impls Postgres; `GET /sources`+`POST /sources` E2E com mapeamento `RepoError → HTTP` 4xx/5xx; 21 unit + 8 integration tests; ledger SQLx fixado em `public._sqlx_migrations` via search_path)_ | 🔽 Low | AI Radar / DevExp | 1d |
| [T-159](2026/Q2/T-159-AI-Radar-Bootstrap-Rust-Workspace.md) | **AI Radar — Bootstrap Rust Workspace** _(workspace Cargo + 3 crates; Axum `/health` 200; tracing JSON com `request_id` correlation; AppConfig figment; Dockerfiles distroless 25.7MB/24.3MB; docker-compose Postgres+API com healthcheck; justfile + README; harness `rust-ai-radar` gate adicionado)_ | 🔽 Low | AI Radar / DevExp | 1d |
| [T-157](2026/Q2/T-157-Longhorn-Quota-Headroom-and-Node3-Recovery.md) | **Longhorn Quota Headroom and Node-3 Recovery** _(quota expandida 8→12Gi; node-3 cordoned; postgres-0 1/1 Running; volume rebuilding 3ª replica)_ | 🚨 Critical | Infra / Storage | 1d |
| [T-156](2026/Q2/T-156-Dependabot-Residual-Cleanup.md) | **Dependabot Residual Cleanup (Tech Debt)** _(arrow2 refactored to polars, all NPM & Rust bumps applied)_ | 🔽 Low | Security / Tech Debt | 1d |
| [T-155](2026/Q2/T-155-React-Static-Toolchain-Security-Migration.md) | **React-Static Toolchain Security Migration** | 🚨 Critical | Security / Frontend | 2d |
| [T-154](2026/Q2/T-154-Dependabot-Security-Remediation-Program.md) | **Dependabot Security Remediation Program** | 🚨 Critical | Security / DevExp | 3d |
| [T-151](2026/Q2/T-151-Ingress-Edge-Decoupling-from-Master.md) | **Ingress Edge Decoupling from Master** _(audit completa: OCI LB externo confirmado, nodeSelector: k8s-master removido, ingress-nginx-controller-workers adicionado ao repo, ambos os pods Running com endpoints ativos)_ | 🔼 High | Infra | 4h |
| [T-150](2026/Q2/T-150-Master-Rootfs-Dependency-Reduction.md) | **Master Rootfs Dependency Reduction** _(MinIO migrado do rootfs do master para PVC Longhorn `minio-pvc-longhorn` 12Gi; dataset legado arquivado e removido do `/data/minio` em 2026-04-26)_ | 🔼 High | Infra | 1d |
| [T-141](2026/Q2/T-141-Repo-Quality-Harness-and-Delivery-Gates-Program.md) | **Repo Quality Harness & Delivery Gates Program** _(plano mestre faseado para checks locais, CI, DoD e smoke gates por stack)_ | 🔼 High | DevExp / Tooling | 1d |
| [T-153](2026/Q2/T-153-MinIO-Longhorn-Gate-Correction-and-Nexus-Exhaustion.md) | **MinIO Longhorn Gate Correction and Nexus Exhaustion** _(gate `storageAvailable` provado como falso verde para `12Gi` / `longhorn-2`; Nexus cleanup nativo executado com delta `0`)_ | High | Infra | 3h |
| [T-152](2026/Q2/T-152-ETCD-Backup-Retention-Drift-Convergence.md) | **ETCD Backup Retention Drift Convergence** _(cronjobs live reconciliados com a IaC versionada; bucket `k8s-backups/etcd` voltou para 4 snapshots lógicos / ~1019 MiB)_ | High | Infra | 3h |
| [T-149](2026/Q2/T-149-Master-DiskPressure-Recurrence-Hardening.md) | **Master DiskPressure Recurrence Hardening** _(recorrencia fechada; cleaner/watchdog endurecidos; master saiu de `DiskPressure` e cluster voltou a warning-only)_ | High | Ops | 4h |
| [T-148](2026/Q2/T-148-Harness-Execution-Summary.md) | **Harness Execution Summary** | High | DevExp / Tooling | 2h |
| [T-147](2026/Q2/T-147-yamllint-gate-for-K8s-manifests.md) | **yamllint gate for K8s manifests** | 🔼 High | DevExp / Tooling | 2h |
| [T-146](2026/Q2/T-146-CI-path-aware-required-checks-rollout.md) | **CI path-aware required checks rollout** | 🔼 High | DevExp / Tooling | 4h |
| [T-145](2026/Q2/T-145-JS-TS-script-convergence.md) | **JS/TS script convergence** | 🔼 High | DevExp / Tooling | 4h |
| [T-144](2026/Q2/T-144-Shell-TUI-quality-gates.md) | **Shell TUI quality gates** | 🔼 High | DevExp / Tooling | 4h |
| [T-143](2026/Q2/T-143-rs-observability-api-modularization-for-testability.md) | **rs-observability-api modularization for testability** | 🔼 High | DevExp / Observability | 6h |
| [T-142](2026/Q2/T-142-Repo-Root-Harness-Minimum-Viable-Verify.md) | **Repo Root Harness Minimum Viable Verify** | 🔼 High | DevExp / Tooling | 4h |
| [T-140](2026/Q2/T-140-Persistent-MCP-Browser-Trust-for-Internal-dnor-CA.md) | **Persistent MCP Browser Trust for Internal dnor CA** | 🔼 High | DevExp / Tooling | 2h |
| [T-139](2026/Q2/T-139-Observability-Console-Ultrawide-UX-and-Text-Visibility-Pass.md) | **Observability Console Ultrawide UX and Text Visibility Pass** | 🔼 High | DevExp / Observability | 3h |
| [T-138](2026/Q2/T-138-Local-Trust-Refresh-for-Internal-dnor-CA.md) | **Local Trust Refresh for Internal dnor CA** | 🔼 High | DevExp / TLS | 1h |
| [T-137](2026/Q2/T-137-Observability-Console-Responsive-Polish-Pass-3.md) | **Observability Console Responsive Polish Pass 3** | 🔼 High | DevExp / Observability | 3h |
| [T-136](2026/Q2/T-136-Observability-Console-Responsive-Polish-and-QA-Report-Hygiene.md) | **Observability Console Responsive Polish and QA Report Hygiene** | 🔼 High | DevExp / Observability | 4h |
| [T-135](2026/Q2/T-135-Observability-Console-Operations-First-UX-Refactor.md) | **Observability Console Operations-First UX Refactor** | 🔼 High | DevExp / Observability | 6h |
| [T-134](2026/Q2/T-134-Observability-Console-Prometheus-Time-Series.md) | **Observability Console Prometheus Time-Series** | 🔼 High | DevExp / Observability | 6h |
|           [T-133](2026/Q2/T-133-Rust-Observability-API-Thin-Slice.md)           | **Rust Observability API Thin Slice** _(Axum API + static UI served in-cluster; ingress `reports.dnor.io` ready pending external DNS)_                     |   🔼 High   |    DevExp / Infra     |   4h   |
|                  [T-105](2026/Q2/T-105-Registry-Resilience.md)                  | **Internal Registry (Nexus) Resilience** _(pre-pull validated; postgres `0 -> 2` recovered with Nexus `0/1` and no `ErrImagePull`)_                        |  🔽 Medium  |         Infra         |   2h   |
|             [T-114](2026/Q2/T-114-OCI-Deploy-Pipeline-Migration.md)             | **OCI Deploy Pipeline: minikube → OCI/Nexus Migration** _(5 apps, deploy.sh, manifest path, registry host)_                                                |   🔼 High   |        DevOps         |   4h   |
|                  [T-115](2026/Q2/T-115-TUI-App-Deploy-Menu.md)                  | **TUI: App Deploy Menu (Dynamic)** _(menu fzf de deploy de apps, status em linha, oci-builder check)_                                                      |  🔽 Medium  |        DevOps         |   3h   |
|                  [T-118](2026/Q2/T-118-TUI-JSLibs-Manager.md)                   | **TUI: js-libs Manager** _(status local vs Nexus, publish via Lerna, check registry health)_                                                               |   🔼 High   |        DevOps         |   2h   |
|              [T-122](2026/Q2/T-122-TUI-Static-Deploy-to-MinIO.md)               | **TUI: Static Deploy para MinIO** _(build + sync do `dist` para `s3://my-site/static/`)_                                                                   |   🔼 High   |     DevOps / TUI      |   3h   |
|                 [T-103](2026/Q2/T-103-CPU-Headroom-Recovery.md)                 | **CPU Headroom Recovery & Sustained Margin Policy** _(recovery complete; watchdog owns ongoing drift detection)_                                           |   🔼 High   |         Infra         |   3h   |
|          [T-120](2026/Q2/T-120-Nginx-Image-Build-Toolchain-Refresh.md)          | **Nginx Image: Build Toolchain Refresh** _(destravar publish.sh apos quebra por Go `< 1.23`)_                                                              | 🚨 Critical |        DevOps         |   2h   |
|               [T-117](2026/Q2/T-117-Publish-DNorio-Libs-Nexus.md)               | **Publicar @dnorio/\* no Nexus** _(8/8 @dnorio/\* publicados — v0.0.175)_ ✅                                                                               | 🚨 Critical |        DevOps         |   1h   |
|             [T-116](2026/Q2/T-116-Nexus-NPM-Registry-Bootstrap.md)              | **Nexus: Bootstrap NPM Registry** _(npm-repo/proxy/group criados + NpmToken realm)_ ✅                                                                     | 🚨 Critical |        DevOps         |   2h   |
|            [T-132](2026/Q2/T-132-Nexus-Cleanup-Policy-Automation.md)            | **Nexus: Cleanup Policy Automation** _(audit/attach helpers for existing policies; `npm-proxy` first, hosted repos conservative)_                          |   🔼 High   |    Infra / DevOps     |   3h   |
|       [T-124](2026/Q2/T-124-Backup-Retention-Audit-and-ETCD-Recovery.md)        | **Backup Retention Audit & ETCD Recovery** _(ETCD/GDrive restaurados, `k8s-backups` em 8055 MiB, política do bucket Nexus documentada)_                    | 🚨 Critical |         Infra         |   3h   |
|         [T-131](2026/Q2/T-131-Helm-Tunnel-Kubeconfig-Compatibility.md)          | **Helm Tunnel Kubeconfig Compatibility** _(local Helm `v3.14.3` incompatível com `kubeconfig_tunnel.yaml`; wrapper `v3.19.0` fixado no repo)_              | 🚨 Critical |    Infra / DevOps     |   2h   |
|  [T-130](2026/Q2/T-130-Watchdog-Signal-Quality-and-False-Positive-Cleanup.md)   | **Watchdog Signal Quality and False Positive Cleanup** _(VolumeAttachment/job/restart signal cleanup)_                                                     |   🔼 High   | Observability / Infra |   4h   |
| [T-129](2026/Q2/T-129-Observability-Report-Modularization-and-API-Readiness.md) | **Observability Report Modularization & API Readiness** _(health report + catalog desacoplados, testáveis e prontos para backend/frontend)_                |   🔼 High   |    DevExp / Infra     |   6h   |
|             [T-128](2026/Q2/T-128-Cluster-Yellow-State-Cleanup.md)              | **Cluster Yellow-State Cleanup** _(kube-apiserver probe, cert-manager quota, postgres snapshot warnings)_                                                  |   🔼 High   |         Infra         |   4h   |
|        [T-127](2026/Q2/T-127-Backup-Retention-Review-MinIO-vs-GDrive.md)        | **Backup Retention Review — MinIO vs GDrive** _(GDrive espelha quase 1:1 o MinIO; retain=7 nao bate com 17-20 backups; revisar Coroot/Kubecost/ETCD)_      | 🚨 Critical |         Infra         |   3h   |
|             [T-126](2026/Q2/T-126-MinIO-Bucket-Provisioning-IaC.md)             | **MinIO: Provisionamento de bucket `my-site` via IaC** _(Job `minio-bootstrap-buckets` — idempotente, mc anonymous set download, ttl 5min)_                |   🔼 High   |    DevOps / Infra     |   1h   |
|            [T-121](2026/Q2/T-121-My-Site-Ingress-TLS-for-dnor.io.md)            | **My Site Ingress: TLS para `dnor.io`** _(Ingress com cert-manager interno Ready; borda publica validada com certificado confiavel)_                       | 🚨 Critical |        DevOps         |   2h   |
|      [T-125](2026/Q2/T-125-Back-End-APM-Optional-and-Service-Recovery.md)       | **Back-End: APM optional + service recovery** _(`optional: true` no APM secretKeyRef — back-end Running após 39h em CreateContainerConfigError)_           | 🚨 Critical |        DevOps         |   1h   |
|     [T-123](2026/Q2/T-123-Static-Deploy-Endpoint-Review-and-Env-Unblock.md)     | **Static Deploy: endpoint review + env unblock** _(migrar de `minio.localhost` para `minio.dnor.io` — bucket criado + upload validado `dnor.io` HTTP 200)_ | 🚨 Critical |     DevOps / TUI      |   2h   |
|             [T-119](2026/Q2/T-119-TUI-App-Deploy-Execution-Logs.md)             | **TUI: App Deploy Execution Logs** _(stream ao vivo + persistencia local no host)_                                                                         |   🔼 High   |        DevOps         |   2h   |
|                [T-113](2026/Q2/T-113-Catalog-Deploy-Actions.md)                 | **Catalog: Deploy Actions para apps deployable** _(copy cmd, vscode link)_                                                                                 |  🔽 Medium  |        DevExp         |   3h   |
|         [T-112](2026/Q2/T-112-Catalog-Namespace-And-ClusterOnly-Fix.md)         | **Catalog: Namespace extraction fix & cluster-only zero** _(chain-repair → cert-manager)_                                                                  |  🔽 Medium  |        DevExp         |   2h   |
|                  [T-111](2026/Q2/T-111-Catalog-Enrichment.md)                   | **Catalog & Inventory Enrichment** _(HTML SPA, drift detection, 5-state readiness)_                                                                        |   🔼 High   |        DevExp         |   4h   |
|               [T-110](2026/Q2/T-110-Unified-Catalog-Inventory.md)               | **Unified Catalog & Inventory Automation**                                                                                                                 |   🔼 High   |      DevExp/Ops       |   6h   |
|           [T-109](2026/Q2/T-109-Postgres-Snapshot-Image-Recovery.md)            | **Postgres Snapshot Job Image Recovery**                                                                                                                   | 🚨 Critical |         Infra         |   1h   |
|                [T-108](2026/Q2/T-108-Tailscale-Mobile-Access.md)                | **Acesso Mobile às Ferramentas do Cluster via Tailscale**                                                                                                  | 🌟 Feature  |        DevExp         |   2h   |
|                     [T-107](2026/Q2/T-107-PKI-Hardening.md)                     | **PKI Hardening — CA Longevity, Chain Integrity & TUI Workflows**                                                                                          |   🔼 High   |         Infra         |   2h   |
|                [T-106](2026/Q2/T-106-Backup-IaC-Codification.md)                | **Backup Infrastructure Codification (IaC Gap)**                                                                                                           |   🔼 High   |         Infra         |   1h   |
|              [T-104](2026/Q2/T-104-Longhorn-Replica-Integrity.md)               | **Longhorn Replica Integrity Hardening**                                                                                                                   |   🔼 High   |        Storage        |   2h   |
|                [T-102](2026/Q2/T-102-Cluster-Health-Watchdog.md)                | **Cluster Health Watchdog & Proactive Alerting**                                                                                                           | 🚨 Critical |     Observability     |   6h   |
|              [T-040](2026/Q1/T-040-Master-Stability-Proactive.md)               | **Proactive Master Stabilization (PLEG/QoS)**                                                                                                              |   🔼 High   |         Infra         |   1d   |
|                  [T-023](2026/Q1/T-023-Storage-Resilience.md)                   | **Storage Resilience & Longhorn Stabilization**                                                                                                            | 🚨 Critical |         Infra         |   4h   |
|       [T-101](2026/Q1/T-101-Storage-Strategy-Pivot-Remote-over-Local.md)        | **T-101 Storage Strategy Pivot: Remote over Local**                                                                                                        |    high     |    Epic-ZeroWaste     | 1 hour |
|             [T-100](2026/Q1/T-100-Zero-Waste-Resource-Lockdown.md)              | **Zero-Waste Resource Lockdown & Completeness Audit**                                                                                                      | 🚨 Critical |          Ops          |   6h   |
|                                [T-098](task.md)                                 | **WSL Native Chrome MCP Setup**                                                                                                                            | 🌟 Feature  |        DevExp         |   4h   |
|             [T-095](2026/Q1/T-095-Fix-Inventory-Report-Exposure.md)             | **Fix Inventory Report Exposure**                                                                                                                          | 🚨 Critical |          Ops          |   2h   |
|              [T-094](2026/Q1/T-094-Reorganize-Tasks-and-Tools.md)               | **Reorganize Tasks and Tools**                                                                                                                             | 🚨 Critical |          Ops          |   2h   |
|                 [T-054](2026/Q1/T-054-Cluster-Stabilization.md)                 | **Cluster Stabilization & IaC Audit**                                                                                                                      |   🔼 High   |         Infra         |   3h   |
|               [T-053](2026/Q1/T-053-Resource-Optimization-V3.md)                | **Resource Optimization V3 (Elastic/Longhorn/Coroot)**                                                                                                     |   🔼 High   |         Infra         |   2h   |
|                  [T-037](2026/Q1/T-037-Deep-Space-Cleanup.md)                   | **Deep Space Cleanup (Docker/Journald)**                                                                                                                   |   🔽 Low    |          Ops          |   4h   |
|                  [T-015](2025/Q4/T-015-Pyroscope-Profiling.md)                  | **Deploy Pyroscope (Continuous Profiling)**                                                                                                                |   🔼 Med    |         Obs.          |   4h   |
|                    [T-011](2025/Q4/T-011-Secrets-Review.md)                     | **Secrets & GitOps Audit**                                                                                                                                 |   🔒 Sec    |          Sec          |   2h   |

- [x] **[T-052](2026/Q1/T-052-Resource-Optimization-V2.md) Resource Optimization V2 (Tuning & Versioning)**
- [x] **Cleaned up legacy scripts (`patch_longhorn.py`, `reinstall_longhorn.sh` etc)**

- [x] **[T-028](2026/Q1/T-028-TUI-Orphaned-PVC-Cleanup.md) Volume Manager: Orphaned PVC Cleanup (TUI Feature)**
- [x] **[T-027](2026/Q1/T-027-Dynamic-Postgres-Versioning.md) Dynamic Postgres Versioning (Dockerfile Source of Truth)**
- [x] **[T-026](2026/Q1/T-026-Secure-Coroot-Integration.md) Secure Coroot Integration (Zero-Trust Credentials)**
- [x] **[T-025](2025/Q4/T-025-Coroot-Enhancements.md) Implement Robust Coroot Observability (Upsert + Auto-Integrations)**
- [x] **[T-024](2025/Q4/T-024-Fix-Deepflow-Ingestion.md) Fix Deepflow Data Ingestion**
- [x] **[T-022](2025/Q4/T-022-OCI-Rescue-Ops.md) OCI Rescue Operations (Cloud Integration)**
  - Full TUI Rescue Menu (Reboot, Deep Forensics, Live Forensics)
  - Fixed Storage Freeze Diagnosis
- [x] **[T-019](2025/Q4/T-019-Interactive-FinOps-Reports.md) Interactive FinOps Reports (Kubecost TUI)**
  - Batch Right-Sizing
  - Abandoned Workload Suspension (Safe Mode)
- [x] **[T-018](2025/Q4/T-018-Storage-Optimization-Baselines.md) Storage Baselines (Lean Defaults)**
- [x] **[T-017](2025/Q4/T-017-TUI-Volume-Manager.md) Volume Manager (Interactive Resize)**
- [x] **[T-017.1](2025/Q4/T-017.1-Housekeeping-Recovery.md) System Cleaner (Log/Apt Vacuum)**
- [x] **[T-016](2025/Q4/T-016-Storage-Optimization-Audit.md) Storage Optimization (Longhorn Policies + Node Fixes)**
- [x] **[T-012](2025/Q4/T-012-Automate-Kibana-Setup.md) Automate Kibana Setup**
- [x] **[T-009](2025/Q4/T-009-Refactor-Legacy-ECK.md) Refactor Legacy ECK Components**
- [x] **[T-005](2025/Q4/T-005-Cost-Analysis.md) Implement Kubecost & FinOps Audit**
- [x] **[T-004](2025/Q4/T-004-Observability-Setup.md) Revitalize ELK Integration**
- [x] **[T-008](2025/Q4/T-008-Register-Credentials.md) Register ELK Credentials**
- [x] **[T-007](2025/Q4/T-007-Refactor-Observability.md) Refactor Observability to Components**
- [x] **[T-006](2025/Q4/T-006-Expose-ELK-Ingress.md) Expose ELK via Ingress (\*.dnor.io)**
- [x] **[T-003](2025/Q4/T-003-Architecture-Documentation.md) Create Architecture Documentation**
- [x] **[T-002](2025/Q4/T-002-TUI-Testing-Framework.md) Implement BATS Testing Framework**
- [x] **[T-001](2025/Q4/T-001-Fix-Configuration-Drift.md) Remediate Configuration Drift**
- [x] **[T-000](2025/Q4/T-000-Project-Initialization.md) Project Initialization**
- [x] **Upgrade**: Upgraded Coroot to `1.17.6` & Disabled Prometheus (Metrics via Clickhouse).

## Automation & Self-Healing

- [x] **Feature**: Automate Kubernetes Dashboard Healing (Kong CrashLoop detection & fix) <!-- id: 50 -->
- [x] **Feature**: Automate Cluster Chaos Cleanup (Remove Evicted/Failed pods) <!-- id: 51 -->
- [x] **Feature**: Automate Registry Connectivity Fix (/etc/hosts sync) <!-- id: 52 -->
- [x] **Cluster Connection & Diagnostics** (Score: 92/100)
- [x] **Strategic Roadmap Definition**

## 🗄️ Deprioritized (Abandoned/Blocked)

|                     ID                      | Task Name                    | Reason                                              |    Date    |
| :-----------------------------------------: | :--------------------------- | :-------------------------------------------------- | :--------: |
| [T-010](2025/Q4/T-010-Self-Hosted-Pixie.md) | **Deploy Self-Hosted Pixie** | SaaS dependency, no ARM64 CLI, replaced by DeepFlow | 2025-12-07 |

---

> **Legend**: 🚨 Critical, 🔼 High/Med, 🔽 Low
