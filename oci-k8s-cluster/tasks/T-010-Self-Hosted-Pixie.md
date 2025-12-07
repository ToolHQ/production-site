# Task T-010: Deploy Self-Hosted Pixie

**Status**: 🧊 Backlog
**Epic**: Observability
**Estimate**: 1 day

## Description
Deploy Pixie in "Self-Hosted" mode (Pixie Cloud Self-Hosted) to comply with the "No-SaaS" policy. This involves hosting the Vizier Control Plane and the UI within our own cluster (or a management cluster).

## References
- [Self-Hosted Pixie Guide](https://docs.px.dev/installing-pixie/install-guides/self-hosted-pixie/)

## Requirements
1.  **Dependencies**: Check resource requirements (Self-hosted PL is heavy).
2.  **OIDC**: Configure OIDC for authentication (Dex or Keycloak might be needed).
3.  **Ingress**: Expose the Pixie UI via `pixie.dnor.io`.
4.  **TUI**: Update commands to deploy this specific flavor.

## Risks
- **Resource Constraints**: Running a full Pixie Cloud control plane on a limited OCI cluster might starve other workloads. Needs careful capacity planning.
