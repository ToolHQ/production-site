# T-016: Storage Optimization Audit (URGENT)

**Status**: To Do
**Priority**: 🚨 CRITICAL
**Owner**: Infrastructure Team
**Estimated**: 4h

## Objective
Audit and optimize all Longhorn PVCs across the cluster to eliminate storage waste. Current state shows significant over-provisioning (e.g., volumes with 100GB allocated but only 5GB used).

## Problem Statement
Based on Longhorn dashboard analysis:
- Multiple volumes show high allocation but low actual usage
- Examples from screenshots:
  - `pvc-8f4b0f2c...`: 100Gi allocated, only ~5Gi used
  - `pvc-4f4d0c2e...`: 50Gi allocated, minimal usage
  - Multiple volumes in "degraded" state
- Total cluster storage being wasted on over-provisioned PVCs

## Requirements
1. **Audit Phase**:
   - List all PVCs with `kubectl get pvc -A`
   - For each PVC, check actual usage vs allocated size
   - Document findings in spreadsheet/table
   
2. **Optimization Phase**:
   - Identify PVCs that can be shrunk (note: requires backup/restore for most storage classes)
   - Update component values files with realistic storage sizes
   - Create migration plan for volumes that need resizing

3. **Components to Review**:
   - Elasticsearch (likely over-provisioned)
   - Nexus
   - MinIO
   - Postgres
   - Kubecost
   - Any other stateful workloads

## Implementation Steps
- [ ] Run storage audit script to collect PVC usage data
- [ ] Create findings table (PVC name, namespace, allocated, used, % waste)
- [ ] Identify top 5 wasteful volumes
- [ ] Update Helm values/manifests with optimized sizes
- [ ] Document safe resizing procedure (backup → delete PVC → recreate smaller → restore)
- [ ] Execute resizing for non-critical volumes first
- [ ] Monitor cluster storage health post-optimization

## Expected Outcome
- Reduce total allocated storage by 30-50%
- All volumes sized appropriately (usage + 20% headroom)
- Improved Longhorn health status
- Updated documentation with right-sized defaults

## References
- Longhorn Dashboard: Nodes view showing allocation vs usage
- Longhorn Volumes view showing individual PVC details
