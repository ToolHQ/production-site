# T-104: Longhorn Replica Integrity Hardening

**Status**: [ ] Backlog | **Priority**: 🔼 High | **Owner**: Infra | **Est**: 2h

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

- [ ] Confirm all volumes show `robustness: healthy` (expected: already true post-fix)
- [ ] For each volume, confirm actual replica count matches `spec.numberOfReplicas`
- [ ] Verify replica distribution: each volume's replicas span different nodes
- [ ] Document current state in `reports/longhorn-volume-baseline-2026-Q2.md`

### Phase 2: Engine / Instance-Manager Resilience
The real hardening: prevent a single instance-manager failure from silently blocking volumes.

- [ ] Confirm Longhorn `Settings` for `replica-soft-anti-affinity` — verify current value.
  With 3 worker nodes and 2-replica volumes: hard anti-affinity is safe and recommended
  (replicas go to 2 different nodes; if one node fails, Longhorn rebuilds on the third).
  Document the decision regardless of outcome.
- [ ] Verify that each volume with replicas=2 has replicas on 2 different nodes ✓ (already true)
- [ ] Verify that each volume with replicas=3 has replicas on 3 different nodes ✓ (already true)
- [ ] Add instance-manager health check to T-102 watchdog as top priority detector

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
- [ ] Check `disk.storageAvailable` — current state: node-1=24GB, node-2=14GB, node-3=10.6GB
  Thresholds: 🟡 Warning < 15GB, 🔴 Critical < 10GB. **node-3 is near warning now.**
- [ ] Add disk health check to T-102 watchdog

## ✅ Definition of Done
- [ ] All volumes show `robustness: healthy` (already true post-fix — verify and document)
- [ ] No volume has actual replica count < spec replica count
- [ ] Replica distribution verified: no two replicas of the same volume on the same node
- [ ] Anti-affinity decision documented (hard vs soft trade-off with 3 nodes)
- [ ] Volume baseline doc created in `reports/`
- [ ] All volumes have a successful backup within the last 7 days
- [ ] Instance-manager health check added to T-102 watchdog

## 🔗 Context
- Incident: 2026-04-03 recovery required scale-down/up cycle to break attach deadlock
- Root cause was instance-manager failure, NOT replica distribution (replicas were correct)
- `pvc-23ab203e` (clickhouse) lost 1 of 2 replicas at some point — rebuilt after fix
- Related: T-102 (Watchdog), T-023 (Storage Resilience)
