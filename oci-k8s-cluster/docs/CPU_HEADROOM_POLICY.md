# CPU Headroom Policy

**Established**: 2026-04-04 (post-incident T-103)
**Owner**: Infra
**Related**: T-103, T-100 (Zero-Waste), T-102 (Watchdog)

## Policy

Every node must maintain **≥ 100m free CPU requests** at all times.

This is the Longhorn floor: the `longhorn-instance-manager` requires ~72m CPU to start. Without
this headroom, it enters `error` state — silently blocking volume attachment for all pods on
that node. The 2026-04-03 incident traced a 132-day cascade failure to a node running at 108%
CPU requests with no room for the instance-manager.

## Thresholds

|   Level   | Node CPU Requests                   | Action                                                      |
| :-------: | :---------------------------------- | :---------------------------------------------------------- |
| 🟢 Green  | < 75% (< 600m on 800m nodes)        | Healthy — no action                                         |
| 🟡 Yellow | 75–87.5% (600m–700m)                | Warning — review recent workload changes                    |
|  🔴 Red   | > 87.5% (> 700m, i.e., < 100m free) | **Block new deployments** — immediate right-sizing required |

> The 75%/85% thresholds represent the ideal long-term target. 87.5% (= 700m on 800m nodes)
> is the pragmatic enforcement boundary enforcing the 100m floor.

## Node Capacity Reference

All worker nodes (k8s-node-1/2/3) and master: **800m allocatable CPU**.

| State  | Requests Used | Free     | Status |
| :----- | :------------ | :------- | :----: |
| Green  | ≤ 600m        | ≥ 200m   |   🟢   |
| Yellow | 601–700m      | 100–199m |   🟡   |
| Red    | > 700m        | < 100m   |   🔴   |

## Current Baseline (2026-04-18, post recovery pass)

| Node       | CPU Requests | Free | Status |
| :--------- | :----------- | :--- | :----: |
| k8s-master | 665m (83%)   | 135m |   🟡   |
| k8s-node-1 | 667m (83%)   | 133m |   🟡   |
| k8s-node-2 | 660m (82%)   | 140m |   🟡   |
| k8s-node-3 | 650m (81%)   | 150m |   🟡   |

All nodes are in the Yellow band and above the 100m floor requirement after the 2026-04-18
recovery pass.

## Enforcement

1. **T-102 watchdog** (`cluster_health_check.sh`) runs node headroom checks and alerts via
   Slack/webhook if any node drops below the 100m floor.
2. **TUI node status** (`k8s_ops_menu.sh`) displays headroom % with 🟢/🟡/🔴 coloring.
3. **ResourceQuotas** (see `components/kube-system/resource-quotas.yaml`) are reviewed after
   any right-sizing pass to keep namespace ceilings at `actual + 30% buffer`.

## Right-Sizing Process

When a node enters 🔴:

1. Run `kubectl top pods -A --sort-by=cpu` to find top consumers.
2. Compare requests vs actual in Coroot (or via the T-100 audit script).
3. For any pod where `request > actual_p99 × 1.5`, reduce the request in the component YAML.
4. Apply via `kubectl apply` and verify node headroom recovers.
5. Update `components/kube-system/resource-quotas.yaml` to reflect new ceilings.
