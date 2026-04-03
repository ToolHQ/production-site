# T-103: CPU Headroom Recovery & Sustained Margin Policy

**Status**: [ ] Backlog | **Priority**: 🔼 High | **Owner**: Infra | **Est**: 3h

## 🎯 Objective
All 4 nodes are operating at 70–93% CPU *request* utilization with zero margin for system
components like the Longhorn instance-manager (needs 72m to start). This directly caused
the 132-day cascade failure discovered on 2026-04-03.

Establish and enforce a **20% CPU headroom policy** on every node, using actual usage data
from Coroot to right-size requests without sacrificing stability.

## 🔍 Problem Analysis

### CPU Request Utilization snapshot (2026-04-03, at time of incident investigation)
Numbers shifted after recovery (new replicas scheduled on node-1, nexus/ingress-nginx fixed).

| Node | Used (incident) | Used (post-fix) | Capacity | % post-fix | Headroom |
|---|---|---|---|---|---|
| k8s-master | 740m | ~790m | ~804m | ~98% | ~14m |
| k8s-node-1 | 750m | ~820m | 800m | ~102% | **over-committed** |
| k8s-node-2 | 750m | ~750m | 800m | ~93% | ~50m |
| k8s-node-3 | 970m | 870m | 800m | **108%** | **over-committed** |

> ⚠️ Post-fix, node-1 and node-3 are over-committed (Longhorn instance-manager + new replicas
> added CPU pressure). Run `kubectl describe nodes` for current numbers before executing Phase 2.

### Why this matters
CPU *requests* determine **scheduling** and Kubernetes uses them to decide if a pod fits on a
node. Even if actual usage is 5%, a pod with 100m request cannot be scheduled on a node with
only 50m free. Today: Longhorn instance-manager (72m) couldn't fit → volumes stuck → 3 pods
down for 19 days.

### Target Policy
- **Warning threshold**: node CPU requests > 75% → reduce requests
- **Critical threshold**: node CPU requests > 85% → hard block on new deployments
- **Floor**: always keep ≥ 100m free on every node (Longhorn headroom)

## 📋 Execution Plan

### Phase 1: Actual Usage Audit
Use Coroot or `kubectl top` to compare requested vs actual CPU for every running container.

- [ ] Run `audit_resources.sh` (from T-100) and generate fresh CSV
- [ ] Identify all containers where `request > actual_p99 * 1.5` (over-requested)
- [ ] Flag containers with `request > 50m` on saturated nodes as optimization candidates
- [ ] Document findings in `reports/cpu-audit-2026-Q2.md`

### Phase 2: Request Reduction (Safe Candidates)

Priority targets on `k8s-node-1` (currently **99%** = 792m/800m):
- [ ] **longhorn-ui** (50m req): Low risk — UI only, not data path. Reduce to 25m if P99 < 15m
- [ ] **kubecost-grafana** (20m req): Reduce to 10m or evaluate removing if Coroot covers dashboards
- [ ] **longhorn-manager** (150m req): ⚠️ HIGH RISK — critical control plane for storage. Only
  reduce if Coroot confirms sustained P99 < 80m. Do not reduce below 100m.
- [ ] **coroot-clickhouse** (50m req): ⚠️ RISK — ClickHouse is a columnar DB; query spikes can
  exceed 50m. Verify with Coroot before any reduction. Do NOT reduce below 30m.

Priority targets on `k8s-node-3` (currently **108%** = 870m/800m):
- [ ] **coroot-prometheus-server** (110m req): Evaluate — Coroot uses ClickHouse for metrics;
  verify if Prometheus is still needed or can be replaced by Coroot's native collection
- [ ] **kubecost-cost-analyzer** (120m req): Evaluate — if Kubecost is superseded by Coroot,
  this is the largest safe saving on node-3
- [ ] Identify remaining highest-request pods and audit actual usage vs request

Apply same approach to master and node-2 to reach < 75% requests.

### Phase 3: ResourceQuota Review
ResourceQuotas already exist for all key namespaces (deployed in T-100). Review alignment
with the new headroom policy — quotas may need tightening after Phase 2 reductions.

- [ ] Review existing quotas vs. actual usage post-Phase-2 reductions
- [ ] Tighten `requests.cpu` quotas where the current ceiling is well above actual+buffer
- [ ] Note: `kube-system` quota already exists (1310m/2000m used). Do NOT reduce the ceiling
  below the current usage — static pods (etcd, apiserver) bypass quotas but non-static pods
  (cilium, coredns) are bound by it. Any reduction must account for planned burst headroom.

### Phase 4: Policy Documentation
- [ ] Add "CPU Headroom Policy" to `oci-k8s-cluster/` governance docs
- [ ] Update `k8s_ops_menu.sh` node status view to show headroom % with color coding
  - 🟢 < 75%, 🟡 75–85%, 🔴 > 85%

## ✅ Definition of Done
- [ ] No node exceeds **90% CPU requests** (80% is unachievable without removing workloads —
  node-1 at 99% needs ~92m reduction to reach 90%; safe candidates yield ~85–95m)
- [ ] Every node has **≥ 100m free** at all times (Longhorn instance-manager floor)
- [ ] ResourceQuota ceilings reviewed and aligned with actual usage + 30% buffer
- [ ] Node status TUI shows headroom % with 🟢/🟡/🔴 coloring

## 🔗 Context
- Immediate fix applied: nexus 200m→170m freed 30m on node-1 (commit `7f6b920`)
- The 93% saturation on node-1 was the root cause of the 132-day instance-manager failure
- Related: T-100 (Zero-Waste), T-102 (Watchdog)
