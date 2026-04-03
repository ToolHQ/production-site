# T-102: Cluster Health Watchdog & Proactive Alerting

**Status**: [ ] Backlog | **Priority**: 🚨 Critical | **Owner**: Infra | **Est**: 6h

## 🎯 Objective
Prevent silent, long-running failures like the one discovered on 2026-04-03: the Longhorn
instance-manager on `k8s-node-1` was in `error` state for **132 days** without detection,
causing postgres, nexus, and coroot-clickhouse to be stuck for 19+ days.

The goal is a lightweight watchdog that runs continuously and surfaces critical anomalies
**before they compound** — no external services, just shell + kubectl + systemd timer.

## 🔍 Problem Analysis (Post-Mortem 2026-04-03)

### What failed silently
| Component | Duration | Root Cause |
|---|---|---|
| Longhorn `instance-manager` (node-1) | 132 days in `error` | CPU starvation: 750m/800m used, pod needed 72m |
| `postgres-0`, `nexus`, `coroot-clickhouse` | 19 days in ContainerCreating | Volumes couldn't attach without instance-manager |
| `ingress-nginx-controller` | 19 days Pending | CPU starvation on master (92% requests) |

### Why it wasn't caught
- No automated check for Longhorn `instancemanager` object state
- No alert for pods stuck in non-Running state for > N hours
- No trend monitoring for CPU request headroom per node
- KANBAN showed all tasks as Done, giving false confidence

## 📋 Execution Plan

### Phase 1: Critical State Detectors
Implement a `cluster_health_check.sh` script covering the highest-impact gaps found today.

#### 1.1 Longhorn Component Health
- [ ] Check all `instancemanager.longhorn.io` objects: alert if any state != `running`
- [ ] Check all `volume.longhorn.io` objects: alert if state is `attaching` AND the corresponding
  `volumeattachment` has `creationTimestamp` older than 30 minutes (use `kubectl get volumeattachment
  -o jsonpath` to compare timestamps — avoids false positives during normal attach cycles)
- [ ] Check all `volume.longhorn.io` objects: alert if robustness is `faulted`
- [ ] Check replica counts: alert if `running replicas < spec.numberOfReplicas` AND volume
  state is not `attaching`/`detaching` (exclude transitional states to avoid false positives
  during normal attach cycles — a stateless script cannot track duration)
- [ ] Check `engine.longhorn.io` objects: alert if any state is `error`

#### 1.2 Pod Stuck Detection
- [ ] Alert if any pod is in `ContainerCreating` / `Pending` / `Init:*` AND
  `pod.metadata.creationTimestamp` is older than 2 hours — pod never reached Running, so
  creation time is the correct duration proxy (compare with `date -u` in the script)
- [ ] Alert if any pod has `restartCount > 20` total (kubectl only exposes cumulative count,
  not per-day — use this as a proxy for CrashLoop; combine with pod age for rate estimation)
- [ ] Alert if any pod is in `Error` state AND
  `status.containerStatuses[*].state.terminated.finishedAt` is older than 30 minutes —
  use terminated timestamp (not creationTimestamp) because the pod may have run fine before
  erroring; `kubectl get pod -o jsonpath='{.status.containerStatuses[0].state.terminated.finishedAt}'`

#### 1.3 CPU Headroom per Node
- [ ] 🟡 Alert if any node has `cpu requests > 75%` of allocatable (T-103 warning threshold)
- [ ] 🔴 Alert if any node has `cpu requests > 85%` (T-103 critical threshold — Longhorn instance-manager at risk)
- [ ] Log headroom trend per node (to detect slow creep before it becomes a problem)

#### 1.4 Nexus / Registry Health
- [ ] Check if Nexus pod is Running and ready
- [ ] Alert if any pod has `ErrImagePull` or `ImagePullBackOff` for > 10 minutes

### Phase 2: Integration with TUI
- [ ] Add a "🏥 Health Report" option to `k8s_ops_menu.sh` main menu that runs the watchdog on-demand
- [ ] Display color-coded output: 🟢 OK / 🟡 Warning / 🔴 Critical per component
- [ ] Output should include "Time in current state" for stuck resources

### Phase 3: Automated Scheduled Scan
Run as a **systemd timer on the master node** — not a Kubernetes CronJob. The cluster is CPU-
saturated and a CronJob pod adds scheduling pressure. The master already has kubectl configured
and direct access to the cluster API.

- [ ] Install `cluster_health_check.sh` to `/opt/k8s-ops/` on the master
- [ ] Create a `systemd` timer unit: `k8s-health-check.timer` running every 30 minutes
- [ ] Log output to `/var/log/k8s-health-check.log` with rotation (`logrotate` rule)
- [ ] Optional: append a summary line to a `NodeCondition` or Longhorn annotation visible in k9s

## ✅ Definition of Done
- [ ] `cluster_health_check.sh` detects the exact failures from 2026-04-03 retroactively (dry-run test)
- [ ] TUI shows health report in < 10 seconds
- [ ] systemd timer runs every 30 minutes without errors for 7 consecutive days
- [ ] A simulated stuck instance-manager is detected within the next scan window

> ⚠️ **Deploy T-102 and T-103 together**: the CPU headroom detector (Phase 1.3) will
> immediately fire 🔴 Critical alerts on node-1 (99%) and node-3 (108%) until T-103 is
> executed. Deploy both in the same session to avoid alert fatigue from known issues.

## 🔗 Context
- Root cause fix applied: `components/nexus/nexus.yaml` cpu 200m→170m, `components/ingress-nginx/deploy.yaml` cpu 100m→50m (commit `7f6b920`)
- Related: T-040 (Master Stability), T-023 (Storage Resilience)
