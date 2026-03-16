# Task T-001: Remediate Configuration Drift

**Status**: ✅ Done
**Epic**: Resilience / Stability
**Estimate**: 2 hours

## Problem
The cluster has 4 active nodes (`master`, `node-1`, `node-2`, `node-3`), but the automation scripts (`common.sh`) only reference 3. This means `node-3` is excluded from updates, certificates renewals, and heal operations.

## Plan
1.  **Analyze `common.sh`**: Confirm the missing entry in the `NODES` array.
2.  **Verify SSH Access**: Ensure we have a valid SSH config alias for `oci-k8s-node-3` (match other nodes).
3.  **Update Config**: Add `oci-k8s-node-3` to `common.sh` logic.
4.  **Verify**: Run a non-destructive command (e.g., `uptime`) against all nodes using the updated script.

## Technical Details
- **File**: `oci-k8s-cluster/common.sh`
- **Key Function**: Auto-detection logic (lines 7-19).

## Verification Method
```bash
# Validates that script now sees 4 nodes
source common.sh && echo "${NODES[@]}"
```
