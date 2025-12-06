# OCI K8s Cluster Strategic Roadmap

> [!NOTE]
> This living document tracks the evolution of the cluster from a "Functional Prototype" to a "Production-Grade Platform".

## 🛡️ 1. Security & Access
- [ ] **RBAC Auditing**: Ensure least-privilege for TUI operations.
- [ ] **Network Policies**: Isolate `dev` workloads from `prod` (Minio/Postgres).
- [ ] **Secret Management**: Move away from local files/env vars where possible.
- [ ] **TUI Security**: Add MFA or confirmation steps for destructive actions (e.g., "Nuke Cluster").

## 👁️ 2. Observability & Monitoring
- [ ] **ELK Stack 2.0**:
    - [ ] Revitalize the `eck` (Elastic Cloud on K8s) component.
    - [ ] Optimize Filebeat/Logstash config to reduce resource overhead on ARM64.
- [ ] **Pixie Integration**:
    - [ ] Deploy New Relic Pixie (or standalone) for eBPF-based deep observability without sidecars.
- [ ] **Metrics Server**: Ensure granularity is sufficient for auto-scaling decisions.

## 💰 3. Cost & Efficiency (FinOps)
- [ ] **Kubecost**: Deploy Kubecost (Free Tier) to map spend to namespaces/labels.
- [ ] **Resource Limits**: Audit all deployments for CPU/RAM Requests/Limits to avoid OOM kills or wastage.
- [ ] **OCI Free Tier Auditing**: Automated check to ensure we stay within the "Always Free" boundaries (4 OOCPU, 24GB RAM).

## ⚡ 4. Performance & Reliability
- [ ] **Component Updates**: Regular "Health Weeks" to update Helm charts/manifests (Minio, Nexus, Postgres).
- [ ] **Storage Tuning**:
    - [ ] Benchmark Longhorn vs. Local-Path for I/O heavy workloads (Postgres).
    - [ ] Tune Longhorn replica counts for OCI network conditions.
- [ ] **Ingress Optimization**: Tune NGINX buffers and timeouts.

## 🔄 5. Disaster Recovery (DR)
- [ ] **Backup Automation**:
    - [ ] Formalize CronJobs for Postgres dumps to S3 (Minio).
    - [ ] VolumeSnapshot schedules (Longhorn).
- [ ] **Drill Testing**: Quarterly "Game Days" to restore a service from backup.
- [ ] **GitOps**: Move cluster state definition fully to Git (ArgoCD/Flux optional, but clean scripts essential).

## 🛠️ 6. TUI & Developer Experience (DX)
- [ ] **Testing**: Implement BATS for `k8s_ops_menu.sh` to prevent regressions.
- [ ] **Interactive Maps**: TUI visualizer for node/pod relationships.
- [ ] **One-Click Updates**: Automate the "Safe Node Update" flow further.
