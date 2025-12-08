# T-014: Deploy DeepFlow (eBPF Observability)

**Status**: In Progress
**Priority**: High
**Owner**: Observability Team
**Replaces**: T-010 (Pixie - abandoned due to SaaS dependency)

## Objective
Deploy **DeepFlow** as a self-hosted, eBPF-based observability platform to provide:
- Network flow visualization and service maps
- Distributed tracing (auto-instrumentation via eBPF)
- Application performance monitoring
- Full control over data (No-SaaS compliance)

## Why DeepFlow?
- ✅ **100% Open Source** and self-hosted
- ✅ **eBPF native** (like Pixie) but without Cloud dependency
- ✅ **ARM64 support** (critical for OCI Ampere)
- ✅ **Integrates with Prometheus/Grafana**
- ✅ **Active development** and CNCF sandbox project

## Requirements
1. Deploy DeepFlow Server (control plane)
2. Deploy DeepFlow Agent (eBPF data collector on each node)
3. Configure storage (ClickHouse for metrics/traces)
4. Expose UI via Ingress
5. Integrate with existing observability stack (ELK, Kubecost)

## Implementation Steps
- [ ] Add DeepFlow Helm repo
- [ ] Create custom values for ARM64 and self-hosted mode
- [ ] Deploy DeepFlow Server + ClickHouse
- [ ] Deploy DeepFlow Agent as DaemonSet
- [ ] Configure Ingress for DeepFlow UI
- [ ] Verify eBPF data collection
- [ ] Document access URLs and basic queries

## References
- [DeepFlow GitHub](https://github.com/deepflowio/deepflow)
- [DeepFlow Docs](https://deepflow.io/docs/)
- [Helm Chart](https://github.com/deepflowio/deepflow/tree/main/charts)
