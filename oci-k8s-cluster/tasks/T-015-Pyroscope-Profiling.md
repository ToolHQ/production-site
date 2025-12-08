# T-015: Deploy Pyroscope (Continuous Profiling)

**Status**: In Progress
**Priority**: Medium
**Owner**: Observability Team

## Objective
Deploy **Pyroscope** for continuous profiling to provide:
- CPU and memory flame graphs
- Application performance profiling
- Historical profiling data for debugging
- Integration with Grafana for visualization

## Why Pyroscope?
- ✅ **Open Source** (Grafana Labs project)
- ✅ **Lightweight** and easy to deploy
- ✅ **Complements DeepFlow** (profiling vs tracing)
- ✅ **Multi-language support** (Go, Python, Java, Node.js, etc.)
- ✅ **Self-hosted** with no SaaS dependency

## Requirements
1. Deploy Pyroscope Server
2. Configure persistent storage for profiles
3. Expose UI via Ingress
4. Integrate with Grafana (optional, future)
5. Configure auto-discovery for profiling targets

## Implementation Steps
- [ ] Add Pyroscope Helm repo
- [ ] Create custom values for storage and ARM64
- [ ] Deploy Pyroscope Server
- [ ] Configure Ingress for Pyroscope UI
- [ ] Verify profiling data collection
- [ ] Document how to instrument applications

## References
- [Pyroscope GitHub](https://github.com/grafana/pyroscope)
- [Pyroscope Docs](https://grafana.com/docs/pyroscope/)
- [Helm Chart](https://github.com/grafana/pyroscope/tree/main/operations/pyroscope/helm/pyroscope)
