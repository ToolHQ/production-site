# 📋 OCI Cluster Project Board

**System Status**: 🟢 Healthy | **Next Milestone**: Foundation Stability

## 🏎️ In Progress
| ID | Task Name | Priority | Owner | Est. |
|:--:|:---|:--:|:--:|:--:|

## 📅 Backlog (To Do)
| ID | Task Name | Priority | Epic | Est. |
|:--:|:---|:--:|:---|:--:|


## ✅ Done
| ID | Task Name | Priority | Owner | Est. |
|:--:|:---|:--:|:--:|:--:|
| [T-040](2026/Q1/T-040-Master-Stability-Proactive.md) | **Proactive Master Stabilization (PLEG/QoS)** | 🔼 High | Infra | 1d |
| [T-023](2026/Q1/T-023-Storage-Resilience.md) | **Storage Resilience & Longhorn Stabilization** | 🚨 Critical | Infra | 4h |
| [T-101](2026/Q1/T-101-Storage-Strategy-Pivot-Remote-over-Local.md) | **T-101 Storage Strategy Pivot: Remote over Local** | high | Epic-ZeroWaste | 1 hour |
| [T-100](2026/Q1/T-100-Zero-Waste-Resource-Lockdown.md) | **Zero-Waste Resource Lockdown & Completeness Audit** | 🚨 Critical | Ops | 6h |
| [T-098](task.md) | **WSL Native Chrome MCP Setup** | 🌟 Feature | DevExp | 4h |
| [T-095](2026/Q1/T-095-Fix-Inventory-Report-Exposure.md) | **Fix Inventory Report Exposure** | 🚨 Critical | Ops | 2h |
| [T-094](2026/Q1/T-094-Reorganize-Tasks-and-Tools.md) | **Reorganize Tasks and Tools** | 🚨 Critical | Ops | 2h |
| [T-054](2026/Q1/T-054-Cluster-Stabilization.md) | **Cluster Stabilization & IaC Audit** | 🔼 High | Infra | 3h |
| [T-053](2026/Q1/T-053-Resource-Optimization-V3.md) | **Resource Optimization V3 (Elastic/Longhorn/Coroot)** | 🔼 High | Infra | 2h |
| [T-037](2026/Q1/T-037-Deep-Space-Cleanup.md) | **Deep Space Cleanup (Docker/Journald)** | 🔽 Low | Ops | 4h |
| [T-015](2025/Q4/T-015-Pyroscope-Profiling.md) | **Deploy Pyroscope (Continuous Profiling)** | 🔼 Med | Obs. | 4h |
| [T-011](2025/Q4/T-011-Secrets-Review.md) | **Secrets & GitOps Audit** | 🔒 Sec | Sec | 2h |
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
- [x] **[T-006](2025/Q4/T-006-Expose-ELK-Ingress.md) Expose ELK via Ingress (*.dnor.io)**
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
| ID | Task Name | Reason | Date |
|:--:|:---|:---|:--:|
| [T-010](2025/Q4/T-010-Self-Hosted-Pixie.md) | **Deploy Self-Hosted Pixie** | SaaS dependency, no ARM64 CLI, replaced by DeepFlow | 2025-12-07 |

---
> **Legend**: 🚨 Critical, 🔼 High/Med, 🔽 Low
