# Storage (Longhorn) Tuning
**Managed by:** `commands.sh` (T-100 Zero-Waste Lockdown)

## Overview
This component applies critical resource limits to the Longhorn storage system, which defaults to "Unlimited" CPU usage.

## Configuration Files
- **`longhorn-limit-range.yaml`**: Enforces default limits (`250m` CPU) for any future Longhorn Pods.
- **`longhorn-manager-patch.yaml`**: Patches the `longhorn-manager` DaemonSet to cap CPU at `500m` (burstable).
- **`longhorn-ui-patch.yaml`**: Caps the UI at `150m`.

## Automated Deployment
The `commands.sh` script in this directory:
1. Applies the LimitRange.
2. Patches the DaemonSet and Deployment in-place.
3. Ensures valid configuration persists through upgrades.

## Why?
Without these limits, `longhorn-manager` was observed consuming unbounded CPU during syncs, risking node stability.
