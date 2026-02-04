# T-096: Comprehensive Resource Baseline & Optimization

- **Status**:   Planning/Review
- **Priority**: 🚨 Critical (Cluster Stability)
- **Epic/Owner**: Ops
- **Estimation**: 4h

## Context
The inventory report reveals a significant deficit in the cluster's resource balance. Total CPU limits exceed 500% of physical capacity on some nodes, and critical system components lack CPU limits altogether ("Infinity"). This task establishes a sane baseline with a positive resource balance (Guaranteed-heavy model).

## Component Tuning Table

### 📊 Observability & Monitoring
| Component | Source File | Current (Req/Lim) | Target (Req/Lim) | Cmd |
|---|---|---|---|---|
| **Coroot Node Agent** | `components/coroot/values.yaml` | 40m/1000m | **60m/150m** | `./deploy_components.sh coroot` |
| **Coroot Clickhouse** | `components/coroot/values.yaml` | 100m/1000m | **200m/500m** | `./deploy_components.sh coroot` |
| **Kubecost Analyzer** | `components/kubecost/values.yaml` | 100m/∞ | **150m/400m** | `./deploy_components.sh kubecost` |
| **Kubecost Prom** | `components/kubecost/values.yaml` | 60m/∞ | **100m/300m** | `./deploy_components.sh kubecost` |

### 🪵 Elastic Stack (Logging)
| Component | Source File | Current (Req/Lim) | Target (Req/Lim) | Cmd |
|---|---|---|---|---|
| **Elastic Operator** | `components/elastic-stack/operator.yaml` | 50m/1000m | **100m/300m** | `kubectl apply -f components/elastic-stack/operator.yaml` |
| **Filebeat** | `components/elastic-stack/filebeat.yaml` | 10m/300m | **20m/100m** | `kubectl apply -f components/elastic-stack/filebeat.yaml` |
| **Logstash** | `components/elastic-stack/logstash.yaml` | 100m/1000m | **200m/600m** | `kubectl apply -f components/elastic-stack/logstash.yaml` |
| **Kibana** | `components/elastic-stack/kibana.yaml` | 90m/500m | **100m/300m** | `kubectl apply -f components/elastic-stack/kibana.yaml` |

### 🛡️ System Infrastructure (Modular Components)
| Component | Source File | Current (Req/Lim) | Target (Req/Lim) | Cmd |
|---|---|---|---|---|
| **Cilium** | `components/cilium/cilium-values.yaml` | 150m/∞ | **150m/450m** | Versioned Component Update |
| **CoreDNS** | `components/coredns/coredns-resources.yaml` | 50m/∞ | **50m/150m** | `kubectl apply -f components/coredns/` |
| **Metrics Server** | `components/metrics-server/components.yaml` | 100m/∞ | **100m/250m** | `kubectl apply -f components/metrics-server/` |
| **Control Plane** | `components/kube-system/static-pod-resources.yaml` | Mixed/∞ | **Tuned** | Versioned Component Update |

### 💾 Storage, Registry & Apps
| Component | Source File | Current (Req/Lim) | Target (Req/Lim) | Cmd |
|---|---|---|---|---|
| **Longhorn InstMgr** | `components/longhorn/longhorn.yaml` | 90m/∞ | **150m/500m** | `kubectl apply -f ...` |
| **Longhorn UI** | `components/longhorn/longhorn.yaml` | 50m/∞ | **50m/150m** | `kubectl apply -f ...` |
| **Minio** | `components/minio/minio-resources.yaml` | 100m/500m | **200m/500m** | `kubectl apply -f ...` |
| **Postgres** | `components/postgres/postgres-resources.yaml` | 100m/500m | **150m/450m** | `kubectl apply -f ...` |
| **Nexus** | `components/nexus/nexus.yaml` | 100m/1000m | **200m/600m** | `kubectl apply -f ...` |
| **Local Path** | `components/local-path-provisioner/local-path.yaml` | 50m/∞ | **50m/150m** | `kubectl apply -f ...` |
| **Cert-Manager** | `components/cert-manager/cert-manager.yaml` | 50m/200m | **50m/100m** | `./deploy_components.sh ...` |
| **Dashboard** | `components/kubernetes-dashboard/dashboard.yaml` | 100m/500m | **100m/250m** | `./deploy_components.sh ...` |

## Verification Plan
1. Apply changes to local files and sync to cluster nodes.
2. Run `generate_inventory_report.sh` after deployment.
3. Verify that CPU Limits in Section 6 show a "L" value < 200% of capacity.
4. Confirm no pods are OOM-killed or throttled under normal load.

## Tasks
- [/] Exhaustive mapping of all 12 namespaces to repository source files
- [ ] Decouple `setup_k8s_cluster.sh` logic into `components/` modular manifests
- [ ] Define precise safe margin (positive balance) targets for all components
- [ ] Implement resource tuning in Helm values (`coroot`, `kubecost`, `cilium`)
- [ ] Implement resource tuning in YAML manifests (`longhorn`, `minio`, `coredns`, etc.)
- [ ] Update `setup_k8s_cluster.sh` to reference modular components instead of hardcoded `sed`
- [ ] Apply changes using `deploy_components.sh` and verification loops
- [ ] Generate final inventory report and confirm positive balance state
