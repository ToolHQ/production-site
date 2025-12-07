# Task T-004: Revitalize Observability (ELK & Pixie)

**Status**: 🌗 Partially Done (Pixie needs auth)
**Epic**: Observability
**Estimate**: 3 days

## Description
Restore and enhance the cluster's observability stack. The goal is to have logs (ELK) and deep metrics (Pixie) visible.

## Objectives
1.  **ELK Stack**:
    - Assess current `eck` operator status.
    - Deploy/Fix Elasticsearch & Kibana.
    - Optimize resource usage (ARM64 targets).
2.  **Pixie**:
    - Deploy Pixie CLI and Vizier.
    - Connect to OCI cluster.
    - Verify eBPF data collection.

## Plan
1.  **Diagnosis**: `kubectl get all -n elastic-system` / `pl -n pl system status`.
2.  **Remediation**:
    - If ECK missing: Re-deploy Operator.
    - If ECK broken: Check logs/PVCs.
3.  **Pixie Setup**:
    - Install `px` CLI.
    - `px deploy`.

## Acceptance Criteria
- [ ] Kibana accessible via Port Forward.
- [ ] Elasticsearch Cluster Green/Yellow.
- [ ] Pixie Live View working.
