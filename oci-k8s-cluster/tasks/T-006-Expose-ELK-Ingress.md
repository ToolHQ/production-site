# Task T-006: Expose ELK Stack via Ingress

**Status**: ✅ Done
**Epic**: Observability / Access
**Estimate**: 2 hours

## Description
Configure `ingress-nginx` resources to expose Kibana and Elasticsearch via the `dnor.io` domain, complying with the project's "Ingress-First Policy" for TUI integration.

## Requirements
1.  **Kibana**: Expose at `kibana.dnor.io` (Service: `oci-logs-kb-http`, Port: 5601).
2.  **Elasticsearch**: Expose at `es.dnor.io` (Service: `oci-logs-es-http`, Port: 9200).
3.  **TLS**: Ensure TLS termination (Passport/Cert-Manager or Self-Signed).
4.  **TUI Update**: Verify `k8s_ops_menu.sh` can detect and open these URLs.

## Plan
1.  Create `manifests/logging/ingress.yaml`.
2.  Apply manifest.
3.  Verify access via `curl` (using host header).
