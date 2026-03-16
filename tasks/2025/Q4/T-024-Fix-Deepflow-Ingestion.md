# T-024: Fix Deepflow Data Ingestion

**Status**: In Progress
**Priority**: Critical
**Owner**: Observability Team
**Related**: [T-014](T-014-DeepFlow-Observability.md)

## Objective
Diagnose and fix the communication failure between Deepflow Agents and the Deepflow Server/Controller. Currently, dashboards are empty, and logs indicate `grpc client not connected` and `agent has no proxy_controller_ip`.

## Diagnosis
- **Symptoms**: Empty Deepflow dashboards.
- **Logs**:
  - Agent: `grpc client not connected`
  - Server: `agent(IP) has no proxy_controller_ip`
- **Root Cause**: Misconfiguration in `deepflow-full-values.yaml` preventing Agents from correctly registering or receiving Controller/Ingester IPs.

## Implementation Steps
- [ ] Analyze `deepflow-full-values.yaml` for `controller-ip` or `deepflowServerNodeIPS` configuration.
- [ ] Correct the Agent-to-Server connection settings (DNS/IP).
- [ ] Apply configuration changes (Helm upgrade/Kubectl apply).
- [ ] Verify Agent connectivity (Logs).
- [ ] Confirm Data Ingestion in Grafana Dashboards.

## References
- Deepflow Troubleshooting Guide
