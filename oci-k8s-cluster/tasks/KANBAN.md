# 📋 OCI Cluster Project Board

**System Status**: 🟢 Healthy | **Next Milestone**: Foundation Stability

## 🏎️ In Progress
| ID | Task Name | Priority | Owner | Est. |
|:--:|:---|:--:|:--:|:--:|
| [T-023](T-023-Storage-Resilience.md) | **Storage Resilience & Longhorn Stabilization** | 🚨 Critical | Infra | 4h |
| [T-020](T-020-Security-Hardening.md) | **Security Hardening (SSH/Audit)** | 🔼 High | Sec | 4h |
| [T-021](T-021-Automated-Maintenance.md) | **Automated Maintenance Policies** |  Low | Infra | 2h |

## 📅 Backlog (To Do)
| ID | Task Name | Priority | Epic | Est. |
|:--:|:---|:--:|:---|:--:|
| [T-013](T-013-Log-Archiving-Minio.md) | **Log Archiving & Rehydration** | 🛡️ FinOps | Obs. | 1d |
| [T-015](T-015-Pyroscope-Profiling.md) | **Deploy Pyroscope (Continuous Profiling)** | 🔼 Med | Obs. | 4h |
| [T-011](T-011-Secrets-Review.md) | **Secrets & GitOps Audit** | 🔒 Sec | Sec | 2h |

## ✅ Done
- [x] **[T-025](T-025-Coroot-Enhancements.md) Implement Robust Coroot Observability (Upsert + Auto-Integrations)**
- [x] **[T-024](T-024-Fix-Deepflow-Ingestion.md) Fix Deepflow Data Ingestion**
- [x] **[T-022](T-022-OCI-Rescue-Ops.md) OCI Rescue Operations (Cloud Integration)**
  - Full TUI Rescue Menu (Reboot, Deep Forensics, Live Forensics)
  - Fixed Storage Freeze Diagnosis
- [x] **[T-019](T-019-Interactive-FinOps-Reports.md) Interactive FinOps Reports (Kubecost TUI)**
  - Batch Right-Sizing
  - Abandoned Workload Suspension (Safe Mode)
- [x] **[T-018](T-018-Storage-Optimization-Baselines.md) Storage Baselines (Lean Defaults)**
- [x] **[T-017](T-017-TUI-Volume-Manager.md) Volume Manager (Interactive Resize)**
- [x] **[T-017.1](T-017.1-Housekeeping-Recovery.md) System Cleaner (Log/Apt Vacuum)**
- [x] **[T-016](T-016-Storage-Optimization-Audit.md) Storage Optimization (Longhorn Policies + Node Fixes)**
- [x] **[T-012](T-012-Automate-Kibana-Setup.md) Automate Kibana Setup**
- [x] **[T-009](T-009-Refactor-Legacy-ECK.md) Refactor Legacy ECK Components**
- [x] **[T-005](T-005-Cost-Analysis.md) Implement Kubecost & FinOps Audit**
- [x] **[T-004](T-004-Observability-Setup.md) Revitalize ELK Integration**
- [x] **[T-008](T-008-Register-Credentials.md) Register ELK Credentials**
- [x] **[T-007](T-007-Refactor-Observability.md) Refactor Observability to Components**
- [x] **[T-006](T-006-Expose-ELK-Ingress.md) Expose ELK via Ingress (*.dnor.io)**
- [x] **[T-003](T-003-Architecture-Documentation.md) Create Architecture Documentation**
- [x] **[T-002](T-002-TUI-Testing-Framework.md) Implement BATS Testing Framework**
- [x] **[T-001](T-001-Fix-Configuration-Drift.md) Remediate Configuration Drift**
- [x] **[T-000](T-000-Project-Initialization.md) Project Initialization**
- [x] **Cluster Connection & Diagnostics** (Score: 92/100)
- [x] **Strategic Roadmap Definition**

## 🗄️ Deprioritized (Abandoned/Blocked)
| ID | Task Name | Reason | Date |
|:--:|:---|:---|:--:|
| [T-010](T-010-Self-Hosted-Pixie.md) | **Deploy Self-Hosted Pixie** | SaaS dependency, no ARM64 CLI, replaced by DeepFlow | 2025-12-07 |

---
> **Legend**: 🚨 Critical, 🔼 High/Med, 🔽 Low
