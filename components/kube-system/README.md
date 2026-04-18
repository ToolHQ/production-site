# Kube-System Resource Tuning

**Managed by:** `commands.sh` (T-100 Zero-Waste Lockdown)

## Overview

This component manages the resource constraints for critical system services to prevent "System Reserve" starvation.

## Configuration Files

- **`limit-range.yaml`**: Defines default limits for any Pod running in `kube-system` (e.g. `150m` CPU default limit).
- **`snapshot-controller-patch.yaml`**: Keeps CSI snapshot-controller requests low enough to avoid node headroom regression after recovery rebalancing.
- **`commands.sh`**:
  1. Applies `limit-range.yaml`.
  2. Applies `snapshot-controller-patch.yaml` when the deployment exists.
  3. (Note: Specific patches for `metrics-server` and `coredns` are handled in their own component directories for modularity).

## Resource Targets

- **Max CPU**: ~400m Total (Reserved for System)
- **Metrics Server**: 50m Request / 150m Limit
- **CoreDNS**: 50m Request / 150m Limit
- **Snapshot Controller**: 25m Request / 150m Limit per replica
