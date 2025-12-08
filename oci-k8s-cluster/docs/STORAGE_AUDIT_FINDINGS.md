# Storage Audit Findings Report
**Date**: 2025-12-07  
**Task**: T-016 Storage Optimization Audit

## Executive Summary
- **Total Allocated**: 44Gi
- **Estimated Waste**: ~13Gi (30% reduction possible)
- **Critical Issues**: 4 volumes severely over-provisioned (1-2% usage)

---

## Detailed Findings

| Namespace | PVC Name | Allocated | Used | Usage % | Status | Recommendation |
|-----------|----------|-----------|------|---------|--------|----------------|
| elastic-system | elasticsearch-data-oci-logs-es-default-0 | 5Gi | 55M | 2% | ⚠️ CRITICAL | Reduce to **1Gi** |
| elastic-system | elasticsearch-data-oci-logs-es-default-1 | 5Gi | 55M | 2% | ⚠️ CRITICAL | Reduce to **1Gi** |
| elastic-system | logstash-data-oci-logstash-ls-0 | 1Gi | 36K | 1% | ⚠️ CRITICAL | Reduce to **500Mi** |
| elastic-system | dlq-vol-oci-logstash-ls-0 | 2Gi | 36K | 1% | ⚠️ CRITICAL | Reduce to **500Mi** |
| kubecost | kubecost-cost-analyzer | 5Gi | N/A | N/A | ⚠️ CHECK | Needs manual inspection |
| kubecost | kubecost-prometheus-server | 5Gi | ~4Gi | ~80% | ✅ OK | Keep current size |
| nexus | nexus-pvc | 10Gi | ~1Gi | ~10% | ⚠️ MODERATE | Reduce to **5Gi** |
| postgres | postgres-pvc | 5Gi | ~100Mi | ~2% | ⚠️ CRITICAL | Reduce to **2Gi** |
| minio | minio-pvc | 1Gi | N/A | N/A | ⚠️ CHECK | Needs manual inspection |

---

## Priority Actions

### 🚨 Immediate (High Impact)
1. **Elasticsearch** (2 volumes): 5Gi → 1Gi each = **Save 8Gi**
   - Current: 10Gi total, using ~110M
   - Target: 2Gi total (1Gi per replica)
   - File: `oci-k8s-cluster/manifests/logging/elasticsearch.yaml`

2. **Postgres**: 5Gi → 2Gi = **Save 3Gi**
   - Current: 5Gi, using ~100Mi
   - Target: 2Gi
   - File: `components/postgres/manifests/postgres.yaml`

### ⚠️ Secondary (Medium Impact)
3. **Logstash** (2 volumes): 3Gi → 1Gi total = **Save 2Gi**
   - DLQ: 2Gi → 500Mi
   - Data: 1Gi → 500Mi
   - File: `components/observability/manifests/logstash.yaml`

4. **Nexus**: 10Gi → 5Gi = **Save 5Gi**
   - Current: 10Gi, using ~1Gi
   - Target: 5Gi (allows growth)
   - File: `components/nexus/manifests/nexus.yaml`

### 🔍 Needs Investigation
5. **Kubecost Cost Analyzer**: Manual check required
6. **MinIO**: Manual check required

---

## Total Savings Potential
- **Immediate**: 11Gi (Elasticsearch + Postgres)
- **Secondary**: 7Gi (Logstash + Nexus)
- **Total**: **18Gi reduction** (41% of current allocation)
- **New Total**: 44Gi → 26Gi

---

## Implementation Plan

### Phase 1: Non-Critical Volumes (Safe to resize)
1. Logstash (low risk, minimal data)
2. Postgres (can backup/restore easily)

### Phase 2: Critical Volumes (Requires backup)
1. Elasticsearch (needs snapshot before resize)
2. Nexus (needs backup before resize)

### Resize Procedure (PVC Shrinking)
```bash
# 1. Backup data
kubectl exec -n <namespace> <pod> -- tar czf /backup.tar.gz /data

# 2. Scale down deployment
kubectl scale deployment <name> -n <namespace> --replicas=0

# 3. Delete PVC (data will be lost!)
kubectl delete pvc <pvc-name> -n <namespace>

# 4. Update manifest with new size
# Edit YAML file

# 5. Apply new PVC
kubectl apply -f <manifest>

# 6. Scale up deployment
kubectl scale deployment <name> -n <namespace> --replicas=1

# 7. Restore data
kubectl exec -n <namespace> <pod> -- tar xzf /backup.tar.gz
```

---

## Next Steps
1. ✅ Audit complete
2. [ ] Update manifest files with optimized sizes
3. [ ] Execute Phase 1 resizing (Logstash, Postgres)
4. [ ] Execute Phase 2 resizing (Elasticsearch, Nexus)
5. [ ] Monitor storage health post-optimization
6. [ ] Update documentation with right-sized defaults
