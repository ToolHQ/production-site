# T-010: Deploy Self-Hosted Pixie (No-SaaS)

**Status**: In Progress
**Priority**: High (Datadog alternative)
**Owner**: Observability Team

## Objective
Deploy Pixie "Vizier" (the eBPF collector and query engine) in a completely self-hosted manner. The user wants the capabilities of Datadog (deep network monitoring, service maps, localized debugging) without sending data to Pixie Cloud (SaaS).

## Constraints & Context
- **Strict No-SaaS Policy**: Data must stay in the cluster.
- **TUI Integration**: Management via `k8s_ops_menu.sh`.
- **Architecture**: ARM64 (Oracle Cloud Ampere).
- **Challenge**: Pixie is primarily designed to work with Pixie Cloud. "Self-Hosted" typically means hosting the Cloud part yourself (complex) or running in "Headless/Vizier-only" mode and using the CLI.

## Requirements
1.  **Deploy Vizier**: Install Pixie Vizier on the cluster using Helm or `px deploy`.
2.  **No-Cloud Configuration**: Ensure it does not try to connect to `withpixie.ai`.
3.  **CLI Access**: Configure `px` CLI to talk directly to the cluster (if possible) or via a self-hosted gateway.
4.  **UI Research**: Investigate if a local UI (e.g., `px-ui` legacy or community fork) is viable. If not, provide robust TUI wrappers for common `px` CLI scripts (e.g., `px/cluster_stats`, `px/net_flow_graph`).

## Implementation Steps
- [ ] **Research**: Verify "Vizier-only" deployment flags and `px` CLI connectivity modes for disconnected environments.
- [ ] **Manifests**: Create `components/observability/pixie_values.yaml` for Helm custom configuration.
- [ ] **Deployment Script**: Update `components/observability/commands.sh` to handle Pixie installation.
- [ ] **Verification**: Run `px live` or similar commands to verify eBPF data ingestion.

## References
- Pixie Air-gapped installation docs.
- `deploy_stats_store` parameter.
