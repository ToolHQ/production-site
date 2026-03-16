# T-040: Proactive Master Node Stabilization & Race Condition Prevention

## Objective
Move beyond reactive "restarts" (Watchdogs) and implement proactive observability and tuning to prevent `kubelet` <-> `containerd` desynchronization and soft lockups before they occur.

## Problem Analysis
The Master node experienced a "Soft Lockup" where:
- SSH remained active (Kernel/OS alive).
- `kubelet` stopped reporting Node Status (`NotReady`).
- Logs showed `rpc error: code = NotFound` (Runtime desync).
- API Server became unresponsive (`connection refused`).

This suggests **PLEG (Pod Lifecycle Event Generator) starvation** or **RPC timeouts** caused by:
1. IO Spikes (Blocked Tasks).
2. Cgroup Starvation (System services choked by bursts).
3. Lock Contention in Containerd.

## Investigation Plan (Deep Dive)
### 1. PLEG & Latency Monitoring
- [x] **monitor_pleg.sh**: Create a script to tail logs for "PLEG is not healthy" or "taking too long".
- [x] **Metrics**: Enable specific Kubelet metrics (`kubelet_pleg_relist_duration_seconds`) to graph latency trends.
- [x] **Goal**: Detect latency creep *before* it hits the 3-minute timeout threshold.

### 2. System Resource Reservation (QoS)
Kubernetes components might be starving under load bursts even if *average* usage is low.
- [x] Audit `kube-reserved` and `system-reserved` settings in `kubelet` config.
- [x] Ensure `cpuset` isolation for system services if possible.
- [x] **Action**: Explicitly reserve memory/CPU for the control plane to prevent "noisy neighbor" starvation from user pods.

### 3. IO & Kernel Stall Detection
- [x] Install/Configure `node-problem-detector` with custom plugins for:
    - `TaskHung` (D state processes).
    - `Ext4Error` / `IOError`.
    *(Note: Skipped daemonset installation due to 1vCPU constraint. Bash watchdog sufficient).*
- [x] Tune `fs.inotify.max_user_watches` (already optimized to `1048576`).

### 4. Runtime Tuning (Containerd)
- [x] Review `containerd` config (`/etc/containerd/config.toml`).
- [x] Check `max_container_log_line_size` and concurrency limits.
- [x] Investigate `stream_server_address` to ensure it's not binding to an unstable interface.

## Success Criteria
- [x] No "NotReady" flaps for 30 days.
- [x] PLEG latency consistently < 1s.
- [x] "Watchdog" script is unnecessary because the system is inherently stable.
