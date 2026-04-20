# T-103: CPU Headroom Recovery & Sustained Margin Policy

**Status**: ✅ Done | **Priority**: 🔼 High | **Owner**: Infra | **Est**: 3h | **Closed**: 2026-04-19

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

### Update 2026-04-18 — Recovery pass completed

Second-pass reductions were applied and validated live until every node returned above the
Longhorn floor:

| Node       | CPU requests    | Free | Policy status  | Actual CPU (`kubectl top`) |
| ---------- | --------------- | ---- | -------------- | -------------------------- |
| k8s-master | 665m/800m (83%) | 135m | 🟡 Above floor | 143m (17%)                 |
| k8s-node-1 | 667m/800m (83%) | 133m | 🟡 Above floor | 221m\*                     |
| k8s-node-2 | 660m/800m (82%) | 140m | 🟡 Above floor | 445m (55%)                 |
| k8s-node-3 | 650m/800m (81%) | 150m | 🟡 Above floor | 270m (33%)                 |

`*` Node-1 runtime usage fluctuated during the final rollouts; the binding check for T-103 is the
scheduler floor (free millicores), which stayed recovered after convergence.

Executed reductions in this recovery pass:

- [x] `pre-pull-share-manager-image` (embedded in `longhorn-manager`): 50m -> 10m
- [x] `snapshot-controller`: 50m -> 10m per replica
- [x] `nexus`: 100m -> 80m
- [x] `longhorn-ui`: 15m -> 10m
- [x] `metrics-server`: 25m -> 20m
- [x] `local-path-provisioner`: 10m -> 5m
- [x] `kubernetes-dashboard-api/web/metrics-scraper`: 10m -> 5m each

Operational note from the attempt matrix:

- A brief attempt to cut `my-site-back-end` and `torproxy` requests was reverted after it created
  noisy rollout blockers (`ImagePullBackOff` on `registry.local` and temporary `default-quota`
  pressure). The stable solution stayed on infrastructure/auxiliary workloads instead.

### Update 2026-04-19 — Post-access regression recovery

After OCI SSH access was restored, the live watchdog exposed a second regression that had been
masked while the master was executing the watchdog via `sudo` without a working kubeconfig.
Once the watchdog bootstrap was fixed, the cluster showed real CPU pressure again:

| Node       | CPU requests    | Free | Policy status              |
| ---------- | --------------- | ---- | -------------------------- |
| k8s-master | 675m/800m (84%) | 125m | 🟡 Above floor / under 85% |
| k8s-node-1 | 472m/800m (59%) | 328m | 🟢 Comfortable margin      |
| k8s-node-2 | 640m/800m (80%) | 160m | 🟡 Above floor / under 85% |
| k8s-node-3 | 610m/800m (76%) | 190m | 🟡 Above floor / under 85% |

Validated live from `/opt/k8s-ops/cluster_health_check.sh` at `2026-04-19 17:23 UTC`:

- No CPU criticals remain in the watchdog.
- Headroom floor (≥100m free) is restored on all nodes again.
- Residual report state is now warning-only: historical restart churn plus Longhorn disk warning
  on `k8s-node-2` (<15 GiB free).

Executed reductions in this follow-up pass:

- [x] `ingress-nginx-controller`: 25m -> 10m
- [x] `longhorn-manager`: 100m -> 60m per node
- [x] `longhorn-driver-deployer`: 20m -> 10m
- [x] `metrics-server`: 20m -> 10m
- [x] `kubecost-prometheus-server`: 100m -> 30m
- [x] `kubecost-grafana`: explicit 5m + 5m requests for main container and sidecar
- [x] `coroot-prometheus-server`: 70m -> 60m

Operational notes:

- `components/metrics-server/commands.sh` is reproducible again after aligning
  `components/metrics-server/components.yaml` to the stable in-cluster port `4443`, which removed
  the `Duplicate value: "https"` failure from the `kubectl apply` path.
- Component scripts that depend on patch files (`components/storage/commands.sh`,
  `components/metrics-server/commands.sh`, `components/kubecost/commands.sh`) now resolve those
  files relative to the component directory instead of depending on the caller's `cwd`.
- `components/kubecost/commands.sh` and repo values were updated, but the immediate live recovery
  for `kubecost-prometheus-server` / `kubecost-grafana` also required direct deployment patches to
  converge within the current maintenance window.
- Follow-up resolved in T-131: local Helm `v3.14.3` was incompatible with
  `oci-k8s-cluster/kubeconfig_tunnel.yaml`, while Helm `v3.19.0` succeeded against the same tunnel.
  The repo now routes Helm-managed component workflows through `tools/helm_compat.sh`, which pins a
  compatible Helm version when the local system binary is too old.

### Closure decision — 2026-04-20

The remaining open item after the 2026-04-19 recovery was not additional implementation work; it
was passive observation time. That monitoring responsibility now belongs to the already-installed
T-102 watchdog on the master (`k8s-health-check.timer` + `/var/log/k8s-health-check.log`).

Closure evidence captured at close-out:

- Live `kubectl describe nodes` / `kubectl top nodes` on 2026-04-19 still showed every node above the
  Longhorn floor: master `675m/800m` requested (`125m` free), node-1 `557m/800m` (`243m` free),
  node-2 `600m/800m` (`200m` free), node-3 `565m/800m` (`235m` free).
- The watchdog timer is active/enabled on the master and last triggered successfully at
  `2026-04-20 00:38 UTC`.
- `/var/log/k8s-health-check.log` shows the final red CPU run at `2026-04-19 17:07 UTC`, immediately
  followed by recovery. From `2026-04-19 17:37 UTC` through `2026-04-20 00:38 UTC`, 15 consecutive
  watchdog runs kept all nodes above `100m` free CPU request headroom.
- Residual warnings in the watchdog are unrelated to CPU floor regression: historical restart churn
  on Longhorn CSI pods and disk-capacity warnings on nodes 2 and 3.

Therefore T-103 is closed as an implementation/recovery task. Ongoing drift detection remains with
T-102 watchdog operations instead of keeping this execution task artificially open for elapsed time.

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

Recovery pass (2026-04-18):

- [x] **longhorn pre-pull helper** (50m): Reduced to 10m — saved 40m/node
- [x] **snapshot-controller** (50m/replica): Reduced to 10m — saved 40m total vs two replicas
- [x] **nexus** (100m): Reduced to 80m — saved 20m
- [x] **longhorn-ui** (15m): Reduced to 10m — saved 5m
- [x] **metrics-server** (25m): Reduced to 20m — saved 5m
- [x] **local-path-provisioner** (10m): Reduced to 5m — saved 5m
- [x] **dashboard api/web/metrics** (10m each): Reduced to 5m each — saved 15m total

Recovery follow-up (2026-04-19):

- [x] **ingress-nginx** (25m): Reduced to 10m — saved 15m on master
- [x] **longhorn-manager** (100m): Reduced to 60m — saved 40m per node
- [x] **longhorn-driver-deployer** (20m): Reduced to 10m — saved 10m
- [x] **metrics-server** (20m): Reduced to 10m — saved 10m
- [x] **kubecost-prometheus-server** (100m): Reduced to 30m — saved 70m
- [x] **kubecost-grafana sidecar + main** (default 10m + 10m): Reduced to 5m + 5m — saved 10m
- [x] **coroot-prometheus-server** (70m): Reduced to 60m — saved 10m while keeping the request
      closer to live usage observed during the follow-up window

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

- [x] Every node has **≥ 100m free** at all times (Longhorn instance-manager floor — implies
      ≤ 700m used on 800m nodes; node-3 at 870m needs ~170m reduction, node-1 at 792m needs ~92m)
      Note: 100m floor is the single binding constraint — "90%" (720m) is more lenient and is
      subsumed by this rule. Validated after the 2026-04-18 recovery pass: master 135m free,
      node-1 133m, node-2 140m, node-3 150m. Re-validated after the 2026-04-19 follow-up:
      master 125m free, node-1 328m, node-2 160m, node-3 190m.
- [x] ResourceQuota ceilings reviewed and aligned with actual usage + 30% buffer
- [x] Node status TUI shows headroom % with 🟢/🟡/🔴 coloring
- [x] Continuous monitoring is now enforced by the T-102 watchdog timer; close-out evidence recorded
  15 consecutive healthy watchdog runs after the final 2026-04-19 recovery, with all nodes
  staying above the `100m` floor and future regressions covered by automated alerts.

## 🔗 Context

- Immediate fix applied: nexus 200m→170m freed 30m on node-1 (commit `7f6b920`)
- The 93% saturation on node-1 was the root cause of the 132-day instance-manager failure
- Related: T-100 (Zero-Waste), T-102 (Watchdog)
