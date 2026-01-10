# T-054: Cluster Stabilization & IaC Audit

**Status**: In Progress
**Priority**: High
**Assignee**: Antigravity

## Objective
Review the entire cluster to identify stability issues (crashes, pending pods, high restarts), resource bottlenecks, and IaC gaps (resources not versioned in `components/`). Stabilize the cluster and ensure all critical components are properly versioned.

## Work Plan

### 1. Discovery & Health Check
- [ ] Check all Pods for Status != Running or High Restarts.
- [ ] Check Node Events/Conditions (Pressure, Taints).
- [ ] Identify Unversioned Workloads (compare with `components/`).

### 2. Stabilization Fixes (Candidates)
- [ ] **Kubecost**: Fix CPU request discrepancy (210m vs 90m).
- [ ] **Longhorn**: Ensure `guaranteed-instance-manager-cpu` is correctly applied (9%).
- [ ] **Nexus**: High disk/CPU usage? (Audit showed 69m on Node 2).
- [ ] **Postgres**: Verify versioning/backup strategy.
- [ ] **Cert-Manager**: Check for expired/failed certificates.

### 3. Versioning (IaC)
- [ ] Ensure any "manual" deployments found are migrated to `components/`.

## Findings Logs
*(To be populated during audit)*
