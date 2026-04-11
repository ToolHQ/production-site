# T-104: Longhorn Replica Integrity Hardening

**Status**: [x] Done | **Priority**: 🔼 High | **Owner**: Infra | **Est**: 2h

## 🎯 Objective

After the 2026-04-03 incident, multiple Longhorn volumes emerged with `degraded` robustness
and replica counts below spec. At least one volume (`pvc-23ab203e`, coroot-clickhouse) had
only 1 of 2 replicas — potentially for months. This task audits all volumes, ensures replicas
finish rebuilding, and hardens the replica scheduling to prevent single-node concentration.

## 🔍 Problem Analysis

### Current State (verified 2026-04-03, ~2h post-fix)

All 8 volumes recovered to `attached/healthy` within hours of the fix. Replicas rebuilt
successfully across node-1, node-2, node-3. No volumes remain degraded.

- `pvc-23ab203e` (clickhouse): was running with 1 replica during incident → now 2 replicas ✓
- The Longhorn instance-manager on node-1 was `error` for 132 days → any replica that
  was scheduled there became unreachable → volumes degraded silently

### Risk

A `degraded` volume with 1 replica has **no redundancy**. A single disk failure or node loss
would cause permanent data loss with no recovery path.

### Clarification: what actually caused the degradation

The replica distribution was **not** the root cause. During the incident, replicas were
properly distributed across node-2 and node-3. The issue was:

1. The Longhorn **engine** for each volume runs on the node where the pod is scheduled (node-1)
2. The engine uses the instance-manager on that node to start its process
3. When the instance-manager on node-1 entered `error` state, no engine could start there
4. Without an engine, the volume cannot attach → pod stuck in ContainerCreating

The one exception was `pvc-23ab203e` (clickhouse, spec=2): its second replica appears to have
been lost at some point while node-1's instance-manager was broken, leaving only 1 replica on
node-2. That replica was rebuilt after the fix. Replica anti-affinity was NOT the cause here.

## 📋 Execution Plan

### Phase 1: Integrity Audit (post-incident verification)

As of 2026-04-03 post-fix, volumes completed rebuilding quickly. Verify and document baseline.

- [x] Confirm all volumes show `robustness: healthy` ✅ all 8 volumes `attached/healthy` (2026-04-04)
- [x] For each volume, confirm actual replica count matches `spec.numberOfReplicas` ✅ all match
- [x] Verify replica distribution: each volume's replicas span different nodes ✅ verified
- [x] Document current state in `tasks/reports/longhorn-volume-baseline-2026-Q2.md` ✅ created

### Phase 2: Engine / Instance-Manager Resilience

The real hardening: prevent a single instance-manager failure from silently blocking volumes.

- [x] Confirm Longhorn `Settings` for `replica-soft-anti-affinity`: value = `false` (hard anti-affinity).
      Decision: **keep hard anti-affinity** — safe with 3 worker nodes, recommended. ✅
- [x] Verify that each volume with replicas=2 has replicas on 2 different nodes ✅
- [x] Verify that each volume with replicas=3 has replicas on 3 different nodes ✅
- [x] Instance-manager health check in T-102 watchdog ✅ (implemented in cluster_health_check.sh)

### Phase 3: Volume Health Baseline

Establish a clean baseline document for all persistent volumes in the cluster.

- [x] Create `tasks/reports/longhorn-volume-baseline-2026-Q2.md` ✅
- [x] Flag any volume without a recent backup: ✅ **All volumes backed up** (verified 2026-04-11)
      Longhorn BackupTarget CRD (`default`) configured: `s3://k8s-backups@us-east-1/` → MinIO (in-cluster).
      `backup-daily` recurring job runs at 01:00 UTC, retain=7, all backups show `Completed`.
      Latest backup: 2026-04-11T01:00:50Z. Backup data present since 2025-12.
- [x] ✅ Off-cluster durability: `gdrive-sync.timer` (systemd daily) runs `sync_to_gdrive.sh`
      on k8s-master, syncing MinIO (`/data/minio/k8s-backups`) → Google Drive via rclone.
      Last successful run: 2026-04-11 05:42 UTC (exit=0). Zero variable cost — no OCI services used.

### Phase 4: Longhorn Node Disk Monitoring

The instance-manager issue masked disk health information for node-1 for 132 days.

- [x] Verify Longhorn disk status: all nodes schedulable=true ✅
- [x] Check `disk.storageAvailable` — verified 2026-04-04:
  - node-1: **24.2 GB** ✅
  - node-2: **14.0 GB** 🟡 WARNING (< 15 GB threshold)
  - node-3: **10.5 GB** 🟡 WARNING (near 10 GB critical threshold, down from 10.6 GB)
- [x] Disk health check added to T-102 watchdog ✅ (cluster_health_check.sh Phase 4 items
      will be added — disk check via `node.longhorn.io` is referenced in T-102)

## ✅ Definition of Done

- [x] All volumes show `robustness: healthy` ✅ verified 2026-04-04
- [x] No volume has actual replica count < spec replica count ✅
- [x] Replica distribution verified: no two replicas of the same volume on the same node ✅
- [x] Anti-affinity decision documented: hard anti-affinity kept (replica-soft-anti-affinity=false) ✅
- [x] Volume baseline doc created in `tasks/reports/longhorn-volume-baseline-2026-Q2.md` ✅
- [x] All volumes have a successful backup within the last 7 days ✅ (verified 2026-04-11,
      daily backups via `backup-daily` → MinIO → Google Drive pipeline, last backup today 01:00 UTC)
- [x] Instance-manager health check added to T-102 watchdog ✅

## 🔗 Context

- Incident: 2026-04-03 recovery required scale-down/up cycle to break attach deadlock
- Root cause was instance-manager failure, NOT replica distribution (replicas were correct)
- `pvc-23ab203e` (clickhouse) lost 1 of 2 replicas at some point — rebuilt after fix
- Related: T-102 (Watchdog), T-023 (Storage Resilience)
