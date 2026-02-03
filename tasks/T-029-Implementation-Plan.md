# IMPL-029: Native PostgreSQL Replication (StatefulSet)

**Linked Task**: [T-029](T-029-Minimizing-Postgres-Risks.md)
**Status**: 🚧 Proposed
**Date**: 2026-01-03

## Goal
Mitigate availability risks identified by Coroot (Single Point of Failure, Data Loss Risk) and enable zero-downtime maintenance by migrating from a single `Deployment` to a replicated `StatefulSet` architecture.

## Strategy: "Native & Lightweight"
To avoid the overhead of heavy operators (like CNPG or Patroni) while ensuring robustness, we will implement **Primary-Standby Replication** using standard PostgreSQL features and Kubernetes StatefulSets.

-   **Architecture**: `StatefulSet` (2 Replicas).
    -   `postgres-0`: Primary (Read/Write).
    -   `postgres-1`: Standby (Read-Only, Async Replication).
-   **Failover**: Manual Promotion (Safe/Simple) / Rolling Updates (Zero Downtime Reads).
-   **Storage**: Separate Volume per Pod via `volumeClaimTemplates`.

## Risks & Mitigations
> [!WARNING]
> **Downtime Required for Migration**: Converting from `Deployment` to `StatefulSet` requires a brief downtime to move data from the old `Deployment` PVC to the new `StatefulSet` PV.
> **Manual Failover**: This design prioritizes *safety* and *simplicity*. If the Primary node fails HARD, manual intervention (running a script) is required to promote the Standby. This avoids "Split-Brain" scenarios common in cheap auto-failover setups.

## Proposed Changes

### Infrastructure
#### [MODIFY] `components/postgres/postgres-resources.yaml`
-   **Change**: `Deployment` -> `StatefulSet`.
-   **Replicas**: 2.
-   **Volume**: Add `volumeClaimTemplates` to generate `postgres-data-postgres-0` and `postgres-data-postgres-1`.
-   **Services**:
    -   `postgres-service` (ClusterIP): Selects `postgres-0` (Write).
    -   `postgres-read` (ClusterIP): Selects `postgres-1` (Read).

### Logic & Scripts
#### [NEW] `components/postgres/entrypoint-wrapper.sh`
-   A smart wrapper script injected into the image.
-   **Logic**:
    1.  Check Pod Hostname (`postgres-0` vs `postgres-1`).
    2.  **If Primary (`-0`)**:
        -   Configure `pg_hba.conf` for replication access.
        -   Create `replicator` user (password from Secret).
        -   Start Postgres normally.
    3.  **If Standby (`-1`)**:
        -   Wait for Primary to be ready.
        -   Run `pg_basebackup` (Clone data from Primary).
        -   Create `standby.signal` / configure `primary_conninfo`.
        -   Start Postgres in Hot Standby mode.

#### [MODIFY] `oci-k8s-cluster/deploy_components.sh`
-   **Credential**: Generate secure `postgres_replication_password` using `credstore.sh`.
-   **Rotation**: Inject this new secret into `postgres-secret`.

#### [MODIFY] `components/postgres/commands.sh`
-   Update Coroot annotations to point to the new StatefulSet logic if necessary.

## Migration Steps (Data Preservation)
1.  **Scale Down**: Scale existing deployment to 0.
2.  **Deploy StatefulSet**: Create `postgres-0` (Empty).
3.  **Data Copy**: Spawn a temporary "Migration Job" that mounts:
    -   Old `postgres-pvc` (Source).
    -   New `postgres-data-postgres-0` (Target).
    -   Running `rsync -av` to preserve all data.
4.  **Start Primary**: `postgres-0` starts with old data.
5.  **Start Replica**: `postgres-1` clones from `postgres-0`.

## Verification Plan
1.  **Replication Status**: Check `pg_stat_replication` on Primary.
2.  **Coroot Check**: Ensure "Postgres isn't replicated" warning disappears.
3.  **Data Integrity**: Verify tables exist on both Primary and Replica.
