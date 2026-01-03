# Task T-029: Minimizing Postgres Risks with Replication

**Status**: 🚧 Planned
**Epic**: Reliability / Infra
**Estimate**: 3 hours
**Owner**: Infra

## Description
Coroot has identified critical availability risks: "Postgres isn't replicated" and "not resilient to node failure". To address this without introducing heavy operator overhead, we will migrate the existing Postgres Deployment to a native **Primary-Standby StatefulSet**. This ensures data redundancy and enables smoother updates.

## Requirements

1.  **Native Replication**:
    -   Use standard PostgreSQL Streaming Replication (WAL).
    -   Primary Node (`postgres-0`) handles Writes.
    -   Replica Node (`postgres-1`) handles Reads and Failover potential.

2.  **Zero-Touch Bootstrapping**:
    -   Replica must automatically clone data (`pg_basebackup`) from Primary on startup if empty.
    -   No manual configuration of `recovery.conf`/`standby.signal` required post-deploy.

3.  **Cost Efficiency**:
    -   Avoid "Heavy" operators (Patroni/Stolon) to minimize RAM/CPU usage.
    -   Use simple bash logic in the container entrypoint.

4.  **Credential Security**:
    -   Replication user (`replicator`) must use a secure, randomly generated password from `credstore.sh`.

## Implementation Details

-   **Architecture**: `StatefulSet` with 2 Replicas.
-   **Services**:
    -   `postgres-service` (5432) -> Points to `postgres-0`.
    -   `postgres-read` (5432) -> Points to `postgres-1` (Optional, for future use).
-   **Migration**:
    -   Requires one-time outage to `rsync` data from Deployment PVC to StatefulSet PVC.

## Verification
-   [ ] Coroot "Availability Risk" alerts are resolved.
-   [ ] `select * from pg_stat_replication` shows the standby connected.
-   [ ] Data written to Primary appears on Standby.
