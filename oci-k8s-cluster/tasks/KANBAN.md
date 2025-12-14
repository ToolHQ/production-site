# 📋 OCI Cluster Project Board

**System Status**: 🟢 Healthy | **Next Milestone**: Foundation Stability

## 🏎️ In Progress
| ID | Task Name | Priority | Owner | Est. |
|:--:|:---|:--:|:--:|:--:|
| [T-020](tasks/T-020-Security-Hardening.md) | **Security Hardening (SSH/Audit)** | 🔼 High | Sec | 4h |
| [T-021](tasks/T-021-Automated-Maintenance.md) | **Automated Maintenance Policies** |  Low | Infra | 2h |

## 📅 Backlog (To Do)
| ID | Task Name | Priority | Epic | Est. |
|:--:|:---|:--:|:---|:--:|
| [T-013](tasks/T-013-Log-Archiving-Minio.md) | **Log Archiving & Rehydration** | 🛡️ FinOps | Obs. | 1d |
| [T-015](tasks/T-015-Pyroscope-Profiling.md) | **Deploy Pyroscope (Continuous Profiling)** | 🔼 Med | Obs. | 4h |
| [T-011](tasks/T-011-Secrets-Review.md) | **Secrets & GitOps Audit** | 🔒 Sec | Sec | 2h |

## ✅ Done
- [x] **T-019: Interactive FinOps Reports (Kubecost TUI)**
  - Batch Right-Sizing
  - Abandoned Workload Suspension (Safe Mode)
- [x] **T-018: Node Disk Manager (Image Pruning)**
- [x] **T-017: Volume Manager (Interactive Resize)**
- [x] **T-017.1: System Cleaner (Log/Apt Vacuum)**
- [x] **T-016: Storage Optimization (Longhorn Policies + Node Fixes)**
- [x] **[T-012](tasks/T-012-Automate-Kibana-Setup.md) Automate Kibana Setup**
- [x] **[T-009](tasks/T-009-Refactor-Legacy-ECK.md) Refactor Legacy ECK Components**
- [x] **[T-005](tasks/T-005-Cost-Analysis.md) Implement Kubecost & FinOps Audit**
- [x] **[T-004](tasks/T-004-Observability-Setup.md) Revitalize ELK Integration**
- [x] **[T-008](tasks/T-008-Register-Credentials.md) Register ELK Credentials**
- [x] **[T-007](tasks/T-007-Refactor-Observability.md) Refactor Observability to Components**
- [x] **[T-006](tasks/T-006-Expose-ELK-Ingress.md) Expose ELK via Ingress (*.dnor.io)**
- [x] **[T-003](tasks/T-003-Architecture-Documentation.md) Create Architecture Documentation**
- [x] **[T-002](tasks/T-002-TUI-Testing-Framework.md) Implement BATS Testing Framework**
- [x] **[T-001](tasks/T-001-Fix-Configuration-Drift.md) Remediate Configuration Drift**
- [x] **[T-000](tasks/T-000-Project-Initialization.md) Project Initialization**
- [x] **Cluster Connection & Diagnostics** (Score: 92/100)
- [x] **Strategic Roadmap Definition**

## 🗄️ Deprioritized (Abandoned/Blocked)
| ID | Task Name | Reason | Date |
|:--:|:---|:---|:--:|
| [T-010](tasks/T-010-Self-Hosted-Pixie.md) | **Deploy Self-Hosted Pixie** | SaaS dependency, no ARM64 CLI, replaced by DeepFlow | 2025-12-07 |

---
> **Legend**: 🚨 Critical, 🔼 High/Med, 🔽 Low
