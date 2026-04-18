# T-103: CPU Headroom Recovery & Sustained Margin Policy

**Status**: [~] In Progress (Phases 1-4 done; 2026-04-18 re-baseline shows nodes 1/2/3 below the 100m floor) | **Priority**: 🔼 High | **Owner**: Infra | **Est**: 3h

## 🎯 Objective

Nodes are operating at up to 108% CPU _request_ utilization (node-3 post-fix) with zero
margin for system components like the Longhorn instance-manager (needs 72m to start). This
directly caused the 132-day cascade failure discovered on 2026-04-03.

Establish and enforce a **20% CPU headroom policy** on every node, using actual usage data
from Coroot to right-size requests without sacrificing stability.

## 🔍 Problem Analysis

### CPU Request Utilization snapshot (2026-04-03, at time of incident investigation)

Numbers shifted after recovery (new replicas scheduled on node-1, nexus/ingress-nginx fixed).

| Node       | Used (incident) | Used (post-fix) | Capacity | % post-fix | Headroom           |
| ---------- | --------------- | --------------- | -------- | ---------- | ------------------ |
| k8s-master | 740m            | ~790m           | ~804m    | ~98%       | ~14m               |
| k8s-node-1 | 750m            | ~820m           | 800m     | ~102%      | **over-committed** |
| k8s-node-2 | 750m            | ~750m           | 800m     | ~93%       | ~50m               |
| k8s-node-3 | 970m            | 870m            | 800m     | **108%**   | **over-committed** |

> ⚠️ Post-fix, node-1 and node-3 are over-committed (Longhorn instance-manager + new replicas
> added CPU pressure). Run `kubectl describe nodes` for current numbers before executing Phase 2.

### Update 2026-04-18 — Post T-128 Re-baseline

Fresh `kubectl describe node` plus `kubectl top nodes` data shows the cluster is stable at runtime,
but the scheduling margin regressed after the recovery and rescheduling work.

| Node       | CPU requests    | Free | Policy status                | Actual CPU (`kubectl top`) |
| ---------- | --------------- | ---- | ---------------------------- | -------------------------- |
| k8s-master | 665m/800m (83%) | 135m | 🟡 Above target, above floor | 216m (27%)                 |
| k8s-node-1 | 707m/800m (88%) | 93m  | 🔴 Below 100m floor          | 272m (34%)                 |
| k8s-node-2 | 790m/800m (98%) | 10m  | 🔴 Below 100m floor          | 613m (76%)                 |
| k8s-node-3 | 735m/800m (91%) | 65m  | 🔴 Below 100m floor          | 275m (34%)                 |

- `k8s-node-2` is the current scheduler bottleneck and no longer just a legacy incident note.
- The gap between requests and actual usage on nodes 1 and 3 confirms the residual risk is mostly
  allocation policy, not steady-state CPU burn.
- Next execution pass must prioritize request cuts or placement changes on node-2 first, then
  restore the 100m floor on node-3 and node-1.

### Why this matters

CPU _requests_ determine **scheduling** and Kubernetes uses them to decide if a pod fits on a
node. Even if actual usage is 5%, a pod with 100m request cannot be scheduled on a node with
only 50m free. Today: Longhorn instance-manager (72m) couldn't fit → volumes stuck → 3 pods
down for 19 days.

### Target Policy

- **Warning threshold**: node CPU requests > 75% → reduce requests
- **Critical threshold**: node CPU requests > 85% → hard block on new deployments
- **Floor**: always keep ≥ 100m free on every node (Longhorn headroom)

> **Reconciliation**: the 75%/85% thresholds are the ideal long-term targets. The DoD uses
> ≥ 100m free as the pragmatic minimum (≈ 87.5% on 800m nodes). Reaching 85% requires removing
> workloads (Kubecost, Prometheus) which is out of scope here — Phase 2 will reduce pressure
> as much as safely possible, targeting the 100m floor as the first binding goal.

## 📋 Execution Plan

### Phase 1: Actual Usage Audit

Use Coroot or `kubectl top` to compare requested vs actual CPU for every running container.

- [x] Run `audit_resources.sh` (from T-100) and generate fresh CSV
- [x] Identify all containers where `request > actual_p99 * 1.5` (over-requested)
- [x] Flag containers with `request > 50m` on saturated nodes as optimization candidates
- [x] Document findings in `reports/cpu-audit-2026-Q2.md`

### Phase 2: Request Reduction (Safe Candidates)

Priority targets on `k8s-node-1` (currently **99%** = 792m/800m):

- [x] **longhorn-ui** (50m req): Reduced to 15m (actual ~1m) — saved 35m
- [x] **nexus** (170m req): Reduced to 100m (actual ~3m) — saved 70m
- [x] **cilium-agent** (50m req): Reduced to 25m (actual 8-24m, DaemonSet) — saved 25m/node

Priority targets on `k8s-node-3` (currently **108%** = 870m/800m):

- [x] **coroot-prometheus-server** (100m req): Reduced to 70m (actual P99 ~64m) — saved 30m
- [x] **kubecost-cost-analyzer** (120m req): Reduced to 30m+10m (actual ~3m) — saved 80m
- [x] **local-path-provisioner** (50m req): Reduced to 10m — saved 40m
- [x] **longhorn-driver-deployer** (50m req): Reduced to 20m — saved 30m

Master / all nodes:

- [x] **ingress-nginx** (50m): Reduced to 25m — saved 25m
- [x] **coredns** (50m): Reduced to 25m — saved 25m
- [x] **cilium-operator** (50m): Reduced to 25m — saved 25m
- [x] **metrics-server** (50m): Reduced to 25m — saved 25m

### Phase 3: ResourceQuota Review

ResourceQuotas already exist for all key namespaces (deployed in T-100). Review alignment
with the new headroom policy — quotas may need tightening after Phase 2 reductions.

- [x] Review existing quotas vs. actual usage post-Phase-2 reductions
- [x] Tighten `requests.cpu` quotas where the current ceiling is well above actual+buffer
      (longhorn-system 1200m→1000m, nexus 400m→150m, postgres 500m→300m, minio 300m→50m,
      coroot 500m→300m, kubecost 500m→150m, ingress-nginx 300m→50m, cert-manager 200m→100m,
      kubernetes-dashboard 200m→150m — all set to actual+30% buffer)
- [x] Note: `kube-system` quota already exists (1310m/2000m used). Do NOT reduce the ceiling
      below the current usage — static pods (etcd, apiserver) bypass quotas but non-static pods
      (cilium, coredns) are bound by it. Any reduction must account for planned burst headroom.

### Phase 4: Policy Documentation

- [x] Add "CPU Headroom Policy" to `oci-k8s-cluster/` governance docs
      (`oci-k8s-cluster/docs/CPU_HEADROOM_POLICY.md` — thresholds, right-sizing process, current baseline)
- [x] Update `k8s_ops_menu.sh` node status view to show headroom % with color coding
  - 🟢 < 75%, 🟡 75–85%, 🔴 > 85%
- [x] Add Option 10 "Pre-Pull Internal Images on All Nodes" to maintenance menu (T-105 precursor)

## ✅ Definition of Done

- [ ] Every node has **≥ 100m free** at all times (Longhorn instance-manager floor — implies
      ≤ 700m used on 800m nodes; node-3 at 870m needs ~170m reduction, node-1 at 792m needs ~92m)
      Note: 100m floor is the single binding constraint — "90%" (720m) is more lenient and is
      subsumed by this rule. Re-baseline 2026-04-18: master 135m free, node-1 93m, node-2 10m,
      node-3 65m.
- [x] ResourceQuota ceilings reviewed and aligned with actual usage + 30% buffer
- [x] Node status TUI shows headroom % with 🟢/🟡/🔴 coloring
- [ ] ⏳ ≥ 100m demonstrated on all nodes for 7 days (T-102 watchdog running — monitoring window ongoing)

## 🔗 Context

- Immediate fix applied: nexus 200m→170m freed 30m on node-1 (commit `7f6b920`)
- The 93% saturation on node-1 was the root cause of the 132-day instance-manager failure
- Related: T-100 (Zero-Waste), T-102 (Watchdog)
