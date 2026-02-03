# T-052: Resource Optimization V2 (Tuning Requests)

**Status**: In Progress
**Priority**: High
**Assignee**: Antigravity

## Objective
Optimize resource allocation for Longhorn, Coroot, and Kubecost on `k8s-node-1` to resolve CPU pressure (99% usage).
Migrate deployment scripts to versioned `components/` structure.

## Requirements
1. **Longhorn UI**: Implement PodAntiAffinity to ensure pods schedule on distinct nodes.
2. **Coroot Cluster Agent**: Reduce CPU request to `60m`.
3. **Coroot Node Agent**: Reduce CPU request to `90m`.
4. **Kubecost Prometheus**: Reduce CPU request to `60m`.
5. **Coroot Prometheus**: Reduce CPU request to `60m`.
6. **Versioning**: Ensure all changes are versioned in `components/` directory (replacing ad-hoc scripts in `oci-k8s-cluster`).

## Implementation Plan
- [x] Create `components/kubecost/commands.sh` with tuned values.
- [x] Create `components/coroot/values.yaml` and `commands.sh` (tune agents/prometheus).
- [x] Create `components/longhorn/longhorn.yaml` (patched with AntiAffinity and resource limits) and `commands.sh`.
- [x] Cleanup legacy scripts (`reinstall_longhorn.sh`, `install_coroot.sh`, `patch_longhorn.py`).
- [x] Apply changes to cluster.
- [ ] Verify resource usage reduction.

## Results
- Node 1 CPU Usage reduced from 990m to ~960m (and further with component restarts).
- Components fully versioned in local repository.
