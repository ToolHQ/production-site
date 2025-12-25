# Task: Storage Optimization Baselines (Lean Defaults)

**Status**: [X] Done
**Priority**: High
**Effort**: Small
**Description**: 
Update all component manifests (Elastic, Postgres, Nexus, etc.) to use optimized storage requests based on verified usage audits. This prevents over-provisioning in future deployments.

## Checklist
- [x] **Audit**: Review verified usage in `docs/STORAGE_OPTIMIZATION.md`
- [x] **Elasticsearch**: Update to `1Gi` (was 5Gi)
- [x] **Logstash**: Update to `32Mi` (was 2Gi)
- [x] **Kubecost**: Update to `88Mi` / `650Mi` (was 32Gi)
- [x] **Nexus**: Update to `44Mi` (was 10Gi)
- [x] **Postgres**: Update to `256Mi` (was 5Gi)
- [x] **Minio**: Verified at `1Gi` (No change needed)

## Verification
- Checked against live PVC usage.
- Confirmed with user (`task_boundary` screenshot review).
