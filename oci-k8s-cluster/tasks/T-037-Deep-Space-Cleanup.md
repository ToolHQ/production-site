# T-037: Deep Space Cleanup (Docker/Journald)

## Objective
Reclaim significant disk space by targeting "deep" caches often missed by standard cleanup tools (`docker image prune`, `apt autoremove`). Focus on `docker builder prune`, aggressive `journald` vacuuming, and `containerd` content store.

## Problem Analysis
Nodes frequently trigger disk pressure warnings even after running basic cleanup. Analysis reveals space is consumed by:
1.  **Docker Build Cache**: `buildkit` layers not removed by standard prune.
2.  **Journald Logs**: Monthly archives accumulating to GBs.
3.  **Apt Archives**: Cached `.deb` packages.
4.  **Crictl Images**: Unused container images (separate from Docker daemon).

## Implementation Plan

### 1. Enhanced `clean_node.sh`
- [ ] Add `docker builder prune --all --force` (Aggressive build cache removal).
- [ ] Add `journalctl --vacuum-time=2d` (Keep only recent logs).
- [ ] Add `crictl rmi --prune` (Clean K8s image cache).
- [ ] Add `apt-get clean` (Clear local repository of retrieved package files).

### 2. Automation Policy
- [ ] Schedule cleanup via Cron or Systemd Timer (e.g., weekly).
- [ ] Add safety checks (disk usage thresholds) before aggressive pruning.

### 3. Verification
- [ ] Track disk usage before/after on a target node.
- [ ] Ensure build times don't degrade significantly (cache vs space trade-off).

## Success Criteria
- [ ] Recover > 5GB per node on average.
- [ ] Zero "Disk Pressure" taints for 30 days.
