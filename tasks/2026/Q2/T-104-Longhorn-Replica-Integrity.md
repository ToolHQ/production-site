# T-104: Longhorn Replica Integrity Hardening

**Status**: [ ] Backlog | **Priority**: 🔼 High | **Owner**: Infra | **Est**: 2h

## 🎯 Objective
After the 2026-04-03 incident, multiple Longhorn volumes emerged with `degraded` robustness
and replica counts below spec. At least one volume (`pvc-23ab203e`, coroot-clickhouse) had
only 1 of 2 replicas — potentially for months. This task audits all volumes, ensures replicas
finish rebuilding, and hardens the replica scheduling to prevent single-node concentration.

## 🔍 Problem Analysis

### Current State (post-incident)
- 3 volumes attached but `degraded` — replicas rebuilding after the instance-manager recovery
- `pvc-23ab203e` (clickhouse): spec=2, was running with 1 replica (node-2 only)
- The Longhorn instance-manager on node-1 was `error` for 132 days → any replica that
  was scheduled there became unreachable → volumes degraded silently

### Risk
A `degraded` volume with 1 replica has **no redundancy**. A single disk failure or node loss
would cause permanent data loss with no recovery path.

## 📋 Execution Plan

### Phase 1: Immediate Integrity Audit
- [ ] List all volumes with `robustness != healthy`: `kubectl get volume.longhorn.io -n longhorn-system`
- [ ] For each degraded volume, check: current replica count vs spec `numberOfReplicas`
- [ ] Verify all replicas started after the incident are in `running` state (not `stopped`/`error`)
- [ ] Check if rebuilds completed by verifying `volume.status.robustness == healthy` for all volumes

Expected timeline for rebuild completion after 2026-04-03 fix: ~2–4 hours for 2GB volumes.

### Phase 2: Replica Scheduling Hardening
Replicas of the same volume ended up on node-1 only (single point of failure) because
Longhorn's default anti-affinity is `soft`. Make it explicit.

- [ ] Review Longhorn `Settings` for `replica-soft-anti-affinity` — should be `false` (hard)
- [ ] Review `replica-zone-soft-anti-affinity` — set to `false` if zones are configured
- [ ] Verify that each volume with replicas=2 has replicas on 2 different nodes
- [ ] Verify that each volume with replicas=3 has replicas on 3 different nodes
- [ ] For any volume violating distribution, trigger a manual rebuild on the correct node

### Phase 3: Volume Health Baseline
Establish a clean baseline document for all persistent volumes in the cluster.

- [ ] Create `reports/longhorn-volume-baseline-2026-Q2.md` listing:
  - Volume name → PVC → namespace → pod
  - Spec replicas vs actual replicas
  - Nodes where replicas reside
  - Last known backup timestamp
- [ ] Flag any volume without a recent backup (> 7 days)
- [ ] Verify backup target is reachable and recent backups succeeded

### Phase 4: Longhorn Node Disk Monitoring
The instance-manager issue masked disk health information for node-1 for 132 days.

- [ ] Verify Longhorn disk status for all nodes via: `kubectl get node.longhorn.io -n longhorn-system`
- [ ] Check `disk.schedulable` is `true` on all nodes
- [ ] Check `disk.storageAvailable` — flag if any node has < 10GB free on Longhorn disk
- [ ] Add disk health check to T-102 watchdog

## ✅ Definition of Done
- [ ] All volumes show `robustness: healthy` (rebuilds complete)
- [ ] No volume has actual replica count < spec replica count
- [ ] Replica anti-affinity is set to `hard` — no two replicas of the same volume on the same node
- [ ] Volume baseline doc created in `reports/`
- [ ] All volumes have a successful backup within the last 7 days

## 🔗 Context
- Incident: 2026-04-03 recovery required scale-down/up cycle to break attach deadlock
- `pvc-23ab203e` (clickhouse) had only 1 replica during the incident — degraded for unknown duration
- Related: T-102 (Watchdog), T-023 (Storage Resilience)
