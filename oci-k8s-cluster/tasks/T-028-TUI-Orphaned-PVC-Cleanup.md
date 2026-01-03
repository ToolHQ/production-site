# Task T-028: Volume Manager - Orphaned PVC Cleanup

**Status**: ✅ Done
**Epic**: Storage / FinOps
**Estimate**: 1 hour
**Owner**: Infra

## Description
Enhance the TUI Volume Manager to automatically detect and offer cleanup for "Orphaned" PersistentVolumeClaims (PVCs). These are PVCs in a `Lost` or `Bound` state where the backing PV has been manually deleted or lost, consuming quota/etcd space without serving data.

## Requirements

1.  **Detection**:
    -   Identify PVCs with status `Lost`.
    -   Identify PVCs where the `volumeName` does not exist in `kubectl get pv`.

2.  **Safety**:
    -   Ask for explicit confirmation before deletion.
    -   Display size and Age of the orphan.

3.  **TUI Integration**:
    -   Add "Clean Orphaned PVCs" option to `k8s_ops_menu.sh` -> Volume Manager.

## Implementation Details

-   **Script**: `oci-k8s-cluster/scripts/volume_manager/cleanup_orphans.sh`
-   **Integration**:
    -   Called from `tui_volume_manager.sh`.
    -   Uses `kubectl get pvc -o json` to correlate with PVs.

## Verification
-   [x] Identified "Phantom" PVC `postgres-volume-claim`.
-   [x] User successfully removed the orphan via TUI.
-   [x] Confirmed no active data volume was touched.
