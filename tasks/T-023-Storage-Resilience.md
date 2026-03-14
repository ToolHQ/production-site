# ✅ T-023: Storage Resilience & Longhorn Stabilization

**Status**: ✅ Done
**Owner**: Infra Team
**Priority**: 🚨 Critical (Stability)

## Context
Nodes are experiencing "Zombie" freezes caused by `iscsi_eh_cmd_timed_out` and IO Wait spikes. This happens when buildkit or heavy workloads stress the Longhorn volume layer, causing the Kernel to lose connection to the block device and panic/hang.

## Objectives
1. **Optimize iSCSI/Multipath**: Tune kernel timeouts to be more forgiving or fail faster (failover) without freezing the OS.
2. **Longhorn Tuning**: Review Longhorn engine settings, resource limits, and replica timeouts.
3. **BuildKit Isolation**: Prevent CI/CD builds from starving the node of I/O (Use `nice`/`ionice` or dedicated nodes).
4. **Kernel Hardening**: Enable watchdog or panic-on-oops to recover faster from hard freezes.

## Action Plan
- [x] Analyze `iscsiod` and `open-iscsi` configuration on valid nodes. (Timeouts follow best-practices: 15s login/logout, 20s replacement).
- [x] Check Longhorn Manager logs for "Volume Detached" events. (No recent detached events logged).
- [x] Implement "Storage QoS" or IO throttling for non-critical pods. (BuildKit systemd services throttled).
- [x] Verify Multipath configuration (blacklist Longhorn devices to prevent interference). (multipathd is disabled).

## Definition of Done
- [ ] No more `iscsi_eh_cmd_timed_out` crashes under load.
- [ ] BuildKit jobs do not freeze the node.
- [ ] Nodes recover automatically from storage blips without requiring OCI Hard Reset.
