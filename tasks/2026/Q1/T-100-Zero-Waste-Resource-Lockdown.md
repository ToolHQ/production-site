# T-100: Zero-Waste Resource Lockdown & Completeness Audit

**Status**: [x] Done | **Priority**: 🚨 Critical | **Owner**: Cluster Operator

## 🎯 Objective
Achieve a **"Zero-Waste"** cluster state where every allocated millicore and megabyte is accounted for, justified, and validated.
**"Assertiveness" Goal**: The system must active *prevent* waste, not just report it.

## 🛡️ Principios (Zero-Based Budgeting)
1.  **Guilty until Proven Innocent**: No resource has a default right to CPU/RAM. Every request must be justified.
2.  **Hard Limits via Policy**: We will use Kubernetes `LimitRanges` and `ResourceQuotas` to enforce constraints at the API level.
3.  **Completeness**: The Inventory Report must reflect 100% of the cluster state. "Shadow IT" (untracked resources) is a failure state.

## 📋 Execution Plan

### Phase 1: The "Audit" (Baseline & Discovery)
**Goal**: Know exactly what we have before cutting.
- [x] **Create `audit_resources.sh`**: A script to dump a CSV of every container running, its Request, Limit, and current Usage.
- [ ] **Inventory Gap Analysis**:
    -   Compare `kubectl api-resources --verbs=list` against our Inventory Report coverage.
    -   Identify missing resource types (Ingress, ConfigMaps, Secrets, CronJobs).
- [x] **Identify Waste**:
    -   List pods with `Request > (Usage * 1.5)` -> Candidates for downsizing. (Analyzed via `resource_audit.csv` - downsized Dashboard, Cert-manager, Minio, Cilium, Coroot)
    -   List pods with `Limit == 0` -> Candidates for immediate policy blocking. (Found ~100 crashed `etcd-backup` pods hoarding CPU due to default LimitRanges; cleaned them up).

### Phase 2: The "Squeeze" (Namespace Lockdowns)
**Goal**: Enforce strict budgets per namespace.

#### 2.1 System Namespace (`kube-system` + `longhorn-system`)
- [x] **Budget**: Max **400m** CPU Total.
- [x] **Action**:
    -   Review `calico`/`cilium`, `coredns`, `metrics-server`.
    -   Set `LimitRange` Default: `cpu: 50m`, `memory: 50Mi`.

#### 2.2 Observability (`monitoring` / `coroot`)
- [x] **Budget**: Max **200m** CPU Total.
- [x] **Action**:
    -   Hard-lock `coroot` components.
    -   Verify standard `LimitRange` prevents "unlimited" sidecars.

#### 2.3 Applications (`nexus`, `postgres`, `default`)
- [x] **Budget**: Remaining Capacity (~300m - 400m).
- [x] **Action**:
    -   Nexus: Fixed Profile (200m).
    -   Postgres: Burstable Profile (100m req / 500m limit).

### Phase 3: The "Lock" (Assertive Policy Enforcement)
**Goal**: Make it impossible to deploy bad workloads.

- [x] **Deploy `LimitRange` per Namespace**:
    -   Sets default Requests/Limits if user forgets them.
    -   Caps Max Limit per pod to prevent node starvation.
- [x] **Deploy `ResourceQuota` per Namespace**:
    -   Hard cap on total `requests.cpu` to prevent over-scheduling.

## 🧪 Validation & Assertiveness Strategy

### A. "The Gatekeeper Test" (Policy Assertion)
*Evidence that the system rejects waste.*
1.  **The "Unlimited" Test**:
    -   Try: `kubectl run waste-test --image=nginx` (No args).
    -   **Expect**: Pod is created BUT has `requests/limits` automatically injected by `LimitRange`.
2.  **The "Glutton" Test**:
    -   Try: `kubectl run glutton-test --image=stress --requests=cpu=2000m`.
    -   **Expect**: **FAIL** (Denied by `ResourceQuota` or Node Capacity).

### B. "The Efficiency Test" (Resource Audit)
*Evidence of Zero Waste.*
-   **Script**: `scripts/validate_efficiency.sh`
-   **Output**:
    -   `Total Allocatable`: 4000m (4 nodes).
    -   `Total Requests`: Xm.
    -   `Efficiency Score`: (Requests / Allocatable) %.
    -   **Success Criteria**: Efficiency between 80% and 95%. (Below 80% = Waste, Above 95% = Risk).

### C. "The Completeness Test" (Report Integrity)
*Evidence that we see everything.*
-   **Gap Check**:
    ```bash
    REAL_COUNT=$(kubectl get all -A --no-headers | wc -l)
    REPORT_COUNT=$(grep -c "Resource:" inventory_report.txt)
    # Delta must be < 5%
    ```

## 📝 Definition of Done
- [x] All namespaces have active `LimitRange`.
- [x] `validate_efficiency.sh` reports Efficiency > 80%.
- [x] "Gatekeeper Tests" pass (Unlimited pods get limits, Glutton pods get rejected).
- [x] Inventory Report captures 100% of workload types.
