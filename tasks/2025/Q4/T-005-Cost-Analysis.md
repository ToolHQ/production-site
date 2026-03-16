# Task T-005: Implement Kubecost & FinOps Audit

**Status**: ✅ Done
**Epic**: FinOps
**Estimate**: 1 day

## Description
Deploy Kubecost to gain visibility into cluster spending, ensuring we stay within the Oracle Cloud Free Tier limits.

## Requirements
1.  **Deployment**: Use Helm (Component: `kubecost`).
2.  **Configuration**:
    - Enable "Free Tier" mode.
    - Disable heavy components (NetworkCosts, heavy Prometheus if using existing, though creating dedicated might be safer for isolation).
    - **ARM64 Compatibility**: Ensure images support ARM64.
3.  **Access**: Expose via Ingress `cost.dnor.io`.
4.  **TUI Integration**: Add to Component Management.

## Deliverables
- `components/kubecost/commands.sh`
- `components/kubecost/values.yaml` (Optimized)
- `components/kubecost/manifests/ingress.yaml`
- Working URL: `https://cost.dnor.io`
