# Storage Optimization Baselines

This document defines the optimized storage defaults for the OCI K8s Cluster, based on actual usage audits (Dec 2025).
These values are now enforced in the deployment manifests to prevent over-provisioning in future setups.

| Component | PVC Name | Old Default | **Optimized Baseline** | Usage (Approx) |
| :--- | :--- | :--- | :--- | :--- |
| **Elasticsearch** | `elasticsearch-data` | 5Gi | **1Gi** | ~550Mi |
| **Logstash** | `dlq-vol`, `logstash-data` | 2Gi | **32Mi** | < 1Mi |
| **Kubecost** | `kubecost-cost-analyzer` | 32Gi (Helm) | **88Mi** | ~5Mi |
| **Prometheus** | `kubecost-prometheus` | 32Gi (Helm) | **650Mi** | ~400Mi |
| **Nexus** | `nexus-pvc` | 10Gi | **128Mi** | ~25Mi |
| **Postgres** | `postgres-pvc` | 5Gi | **256Mi** | ~40Mi |
| **Minio** | `minio-pvc` | 1Gi | **1Gi** | ~10Mi (Baseline) |

## Maintenance

To apply these changes to an existing cluster, you must:
1.  **Backup** your data (if critical).
2.  **Delete** the old PVCs (Warning: Data Loss).
3.  **Redeploy** the component using `deploy_components.sh`.

Or use the `resize_shrink_v2.sh` script to attempt an in-place shrink (risky).

## Files Modified
*   `components/observability/manifests/elasticsearch.yaml`
*   `components/observability/manifests/logstash.yaml`
*   `components/nexus/nexus-resources.yaml`
*   `components/postgres/postgres-resources.yaml`
*   `components/kubecost/commands.sh` (Optimized Jan 2026: 2Gi)
