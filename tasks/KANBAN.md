# 📋 OCI Cluster Project Board

**System Status**: 🟡 Recovering | **Next Milestone**: Observability & Resilience (Q2 2026)

> **Incident 2026-04-03**: Longhorn instance-manager on node-1 was in `error` for 132 days
> (CPU starvation). postgres, nexus, coroot-clickhouse stuck for 19 days. Fixed in commit `7f6b920`.
> Volumes rebuilding replicas. See T-102/T-103/T-104 for follow-up hardening.

## 🏎️ In Progress

|                       ID                        | Task Name                                                                 | Priority | Owner | Est. |
| :---------------------------------------------: | :------------------------------------------------------------------------ | :------: | :---: | :--: |
| [T-127](2026/Q2/T-127-Backup-Retention-Review-MinIO-vs-GDrive.md) | **Backup Retention Review — MinIO vs GDrive** _(GDrive espelha quase 1:1 o MinIO; retain=7 nao bate com 17-20 backups; revisar Coroot/Kubecost/ETCD)_ | 🚨 Critical | Infra | 3h |
| [T-122](2026/Q2/T-122-TUI-Static-Deploy-to-MinIO.md) | **TUI: Static Deploy para MinIO** _(build + sync do `dist` para `s3://my-site/static/`)_ | 🔼 High | DevOps / TUI | 3h |
| [T-121](2026/Q2/T-121-My-Site-Ingress-TLS-for-dnor.io.md) | **My Site Ingress: TLS para `dnor.io`** _(cert-manager + trust da CA interna)_ | 🚨 Critical | DevOps | 2h |
| [T-120](2026/Q2/T-120-Nginx-Image-Build-Toolchain-Refresh.md) | **Nginx Image: Build Toolchain Refresh** _(destravar publish.sh apos quebra por Go `< 1.23`)_ | 🚨 Critical | DevOps | 2h |
| [T-103](2026/Q2/T-103-CPU-Headroom-Recovery.md) | **CPU Headroom Recovery & Sustained Margin Policy** _(monitoring window)_ | 🔼 High  | Infra |  3h  |

## 🔥 Blocker (Deploy back-end travado)

|                           ID                           | Task Name                                                                              |  Priority   | Epic   | Est. |
| :----------------------------------------------------: | :------------------------------------------------------------------------------------- | :---------: | :----- | :--: |
| [T-116](2026/Q2/T-116-Nexus-NPM-Registry-Bootstrap.md) | **Nexus: Bootstrap NPM Registry** _(npm-repo/proxy/group criados + NpmToken realm)_ ✅ | 🚨 Critical | DevOps |  2h  |
|  [T-117](2026/Q2/T-117-Publish-DNorio-Libs-Nexus.md)   | **Publicar @dnorio/\* no Nexus** _(8/8 @dnorio/\* publicados — v0.0.175)_ ✅           | 🚨 Critical | DevOps |  1h  |

## 📅 Backlog (To Do)

|                           ID                            | Task Name                                                                                                   | Priority  | Epic   | Est. |
| :-----------------------------------------------------: | :---------------------------------------------------------------------------------------------------------- | :-------: | :----- | :--: |


| [T-124](2026/Q2/T-124-Backup-Retention-Audit-and-ETCD-Recovery.md) | **Backup Retention Audit & ETCD Recovery** _(etcd quebrado 53d, GDrive desatualizado 4m, coroot-data 3.9GiB, kubecost 1.3GiB)_ | 🚨 Critical | Infra | 3h |

|      [T-118](2026/Q2/T-118-TUI-JSLibs-Manager.md)       | **TUI: js-libs Manager** _(status local vs Nexus, publish via Lerna, check registry health)_                |  🔼 High  | DevOps |  2h  |
|      [T-115](2026/Q2/T-115-TUI-App-Deploy-Menu.md)      | **TUI: App Deploy Menu (Dynamic)** _(menu fzf de deploy de apps, status em linha, oci-builder check)_       | 🔽 Medium | DevOps |  3h  |
| [T-114](2026/Q2/T-114-OCI-Deploy-Pipeline-Migration.md) | **OCI Deploy Pipeline: minikube → OCI/Nexus Migration** _(5 apps, deploy.sh, manifest path, registry host)_ |  🔼 High  | DevOps |  4h  |
|      [T-105](2026/Q2/T-105-Registry-Resilience.md)      | **Internal Registry (Nexus) Resilience**                                                                    | 🔽 Medium | Infra  |  2h  |

## ✅ Done

|                                 ID                                 | Task Name                                                                                 |  Priority   |     Owner      |  Est.  |
| :----------------------------------------------------------------: | :---------------------------------------------------------------------------------------- | :---------: | :------------: | :----: | --- | ------------------------------------------------- | ------------------------------------------------ | ----------- | ------------- | --- |
| [T-126](2026/Q2/T-126-MinIO-Bucket-Provisioning-IaC.md) | **MinIO: Provisionamento de bucket `my-site` via IaC** _(Job `minio-bootstrap-buckets` — idempotente, mc anonymous set download, ttl 5min)_ | 🔼 High | DevOps / Infra | 1h |
| [T-125](2026/Q2/T-125-Back-End-APM-Optional-and-Service-Recovery.md) | **Back-End: APM optional + service recovery** _(`optional: true` no APM secretKeyRef — back-end Running após 39h em CreateContainerConfigError)_ | 🚨 Critical | DevOps | 1h |
| [T-123](2026/Q2/T-123-Static-Deploy-Endpoint-Review-and-Env-Unblock.md) | **Static Deploy: endpoint review + env unblock** _(migrar de `minio.localhost` para `minio.dnor.io` — bucket criado + upload validado `dnor.io` HTTP 200)_ | 🚨 Critical | DevOps / TUI | 2h |
| [T-119](2026/Q2/T-119-TUI-App-Deploy-Execution-Logs.md) | **TUI: App Deploy Execution Logs** _(stream ao vivo + persistencia local no host)_ | 🔼 High | DevOps | 2h |
|          [T-113](2026/Q2/T-113-Catalog-Deploy-Actions.md)          | **Catalog: Deploy Actions para apps deployable** _(copy cmd, vscode link)_                |  🔽 Medium  |     DevExp     |   3h   |
|  [T-112](2026/Q2/T-112-Catalog-Namespace-And-ClusterOnly-Fix.md)   | **Catalog: Namespace extraction fix & cluster-only zero** _(chain-repair → cert-manager)_ |  🔽 Medium  |     DevExp     |   2h   |
|            [T-111](2026/Q2/T-111-Catalog-Enrichment.md)            | **Catalog & Inventory Enrichment** _(HTML SPA, drift detection, 5-state readiness)_       |   🔼 High   |     DevExp     |   4h   |
|        [T-110](2026/Q2/T-110-Unified-Catalog-Inventory.md)         | **Unified Catalog & Inventory Automation**                                                |   🔼 High   |   DevExp/Ops   |   6h   |
|     [T-109](2026/Q2/T-109-Postgres-Snapshot-Image-Recovery.md)     | **Postgres Snapshot Job Image Recovery**                                                  | 🚨 Critical |     Infra      |   1h   |
|         [T-108](2026/Q2/T-108-Tailscale-Mobile-Access.md)          | **Acesso Mobile às Ferramentas do Cluster via Tailscale**                                 | 🌟 Feature  |     DevExp     |   2h   |
|              [T-107](2026/Q2/T-107-PKI-Hardening.md)               | **PKI Hardening — CA Longevity, Chain Integrity & TUI Workflows**                         |   🔼 High   |     Infra      |   2h   |
|         [T-106](2026/Q2/T-106-Backup-IaC-Codification.md)          | **Backup Infrastructure Codification (IaC Gap)**                                          |   🔼 High   |     Infra      |   1h   |
|        [T-104](2026/Q2/T-104-Longhorn-Replica-Integrity.md)        | **Longhorn Replica Integrity Hardening**                                                  |   🔼 High   |    Storage     |   2h   |     | [T-102](2026/Q2/T-102-Cluster-Health-Watchdog.md) | **Cluster Health Watchdog & Proactive Alerting** | 🚨 Critical | Observability | 6h  |
|        [T-040](2026/Q1/T-040-Master-Stability-Proactive.md)        | **Proactive Master Stabilization (PLEG/QoS)**                                             |   🔼 High   |     Infra      |   1d   |
|            [T-023](2026/Q1/T-023-Storage-Resilience.md)            | **Storage Resilience & Longhorn Stabilization**                                           | 🚨 Critical |     Infra      |   4h   |
| [T-101](2026/Q1/T-101-Storage-Strategy-Pivot-Remote-over-Local.md) | **T-101 Storage Strategy Pivot: Remote over Local**                                       |    high     | Epic-ZeroWaste | 1 hour |
|       [T-100](2026/Q1/T-100-Zero-Waste-Resource-Lockdown.md)       | **Zero-Waste Resource Lockdown & Completeness Audit**                                     | 🚨 Critical |      Ops       |   6h   |
|                          [T-098](task.md)                          | **WSL Native Chrome MCP Setup**                                                           | 🌟 Feature  |     DevExp     |   4h   |
|      [T-095](2026/Q1/T-095-Fix-Inventory-Report-Exposure.md)       | **Fix Inventory Report Exposure**                                                         | 🚨 Critical |      Ops       |   2h   |
|        [T-094](2026/Q1/T-094-Reorganize-Tasks-and-Tools.md)        | **Reorganize Tasks and Tools**                                                            | 🚨 Critical |      Ops       |   2h   |
|          [T-054](2026/Q1/T-054-Cluster-Stabilization.md)           | **Cluster Stabilization & IaC Audit**                                                     |   🔼 High   |     Infra      |   3h   |
|         [T-053](2026/Q1/T-053-Resource-Optimization-V3.md)         | **Resource Optimization V3 (Elastic/Longhorn/Coroot)**                                    |   🔼 High   |     Infra      |   2h   |
|            [T-037](2026/Q1/T-037-Deep-Space-Cleanup.md)            | **Deep Space Cleanup (Docker/Journald)**                                                  |   🔽 Low    |      Ops       |   4h   |
|           [T-015](2025/Q4/T-015-Pyroscope-Profiling.md)            | **Deploy Pyroscope (Continuous Profiling)**                                               |   🔼 Med    |      Obs.      |   4h   |
|              [T-011](2025/Q4/T-011-Secrets-Review.md)              | **Secrets & GitOps Audit**                                                                |   🔒 Sec    |      Sec       |   2h   |

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
