# T-130: Watchdog Signal Quality and False Positive Cleanup

**Status**: [x] Done | **Priority**: 🔼 High | **Owner**: Observability / Infra | **Est**: 4h | **Closed**: 2026-04-18

## 🎯 Objective

Reduce alert fatigue in the cluster watchdog so the Health Report highlights active operational
risk instead of historical residue. The goal is to preserve real cluster pressure signals while
removing known false positives from stale `VolumeAttachment`, terminal `Job` pods, and lifetime
restart counters.

## 🔍 Baseline (2026-04-18)

Live output from `/opt/k8s-ops/cluster_health_check.sh` on the master still reports
`11 critical / 11 warning(s)` even after T-128 closed the original yellow-state backlog.

Confirmed false positives:

- `VolumeAttachment` objects reported as "stuck attaching" even when `status.attached=true`.
- `cert-manager` `chain-repair` pods reported as terminated/error even though the pods are
  `Succeeded` and belong to completed `Job` runs.
- Restart warnings based only on cumulative `restartCount`, including pods whose last restart
  happened months ago and are currently `Running`/`Ready`.

Signals that must remain visible:

- CPU request headroom red on `k8s-node-1`, `k8s-node-2`, `k8s-node-3` (tracked in T-103).
- Longhorn disk warnings on nodes with low free space.
- Recent restart activity on control-plane / CSI pods when the last restart is still recent.

Operational note:

- The master currently runs an older copy of the watchdog at `/opt/k8s-ops/cluster_health_check.sh`.
  The repo version and the installed version must be kept in sync, otherwise the TUI continues to
  show stale logic even after a repo fix.

## Update 2026-04-18 — Result

- Tightened the `VolumeAttachment` rule so it only alerts on objects that are still unattached,
  not deleting, and backed by a Longhorn volume that remains in `state=attaching`.
- Re-deployed the repo watchdog to `/opt/k8s-ops/cluster_health_check.sh` on the master so the TUI
  and the systemd timer stopped using stale logic.
- Confirmed the master-installed script no longer reports completed `chain-repair` jobs as active
  terminated/error pods because it now matches the current repo version.
- Replaced the raw lifetime restart proxy with a recent-restart heuristic; long-idle historical
  restarts dropped out, while recent control-plane / CSI churn still remains visible.
- Live report delta after validation on the master: `11 critical / 11 warning(s)` down to
  `3 critical / 6 warning(s)`.
- Remaining alerts now map to real follow-up work:
  - CPU headroom pressure on nodes 1/2/3 (T-103)
  - Longhorn disk headroom on nodes 2/3 (T-104)
  - recent restart activity on `kube-controller-manager` and `csi-provisioner`

## 📋 Execution Plan

### Phase 1 — Baseline Capture

- [x] Re-run the live Health Report from the master-installed watchdog.
- [x] Confirm the reported `VolumeAttachment` objects are actually `attached=true`.
- [x] Confirm the reported `chain-repair` pods are `Succeeded` `Job` pods.
- [x] Inspect the last restart timestamp of high-restart pods to separate recent churn from
      historical residue.

### Phase 2 — Rule Tightening

- [x] Update the `VolumeAttachment` detector to require all of the following before alerting:
  - `status.attached != true`
  - no `metadata.deletionTimestamp`
  - corresponding Longhorn volume still in `state=attaching`
- [x] Keep terminated-pod warnings focused on active failures, excluding completed/succeeded jobs.
- [x] Replace the raw lifetime restart proxy with a recent-restart heuristic:
      only warn when the pod is not ready or the last restart happened within the active review window.

### Phase 3 — Deploy and Validate

- [x] Sync the patched watchdog to `/opt/k8s-ops/cluster_health_check.sh` on the master.
- [x] Re-run the live report and compare issue counts before/after the patch.
- [x] Leave T-130 open only for residual real signals, not report noise.

## ✅ Definition of Done

- [x] The Health Report no longer raises critical alerts for `VolumeAttachment` objects that are
      already attached.
- [x] Completed `Job` pods no longer appear as active terminated/error warnings.
- [x] Pods with high lifetime `restartCount` but no recent restart no longer inflate the warning set.
- [x] Real red signals from T-103/T-104 still appear after the cleanup.

## 🔗 References

- [oci-k8s-cluster/scripts/observability/cluster_health_check.sh](../../../oci-k8s-cluster/scripts/observability/cluster_health_check.sh)
- [oci-k8s-cluster/scripts/observability/install_health_watchdog.sh](../../../oci-k8s-cluster/scripts/observability/install_health_watchdog.sh)
- [tasks/2026/Q2/T-102-Cluster-Health-Watchdog.md](T-102-Cluster-Health-Watchdog.md)
- [tasks/2026/Q2/T-103-CPU-Headroom-Recovery.md](T-103-CPU-Headroom-Recovery.md)
- [tasks/2026/Q2/T-124-Backup-Retention-Audit-and-ETCD-Recovery.md](T-124-Backup-Retention-Audit-and-ETCD-Recovery.md)
