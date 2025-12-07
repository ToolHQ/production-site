# Task T-013: Log Archiving & Rehydration (MinIO)

**Status**: 🧊 Backlog
**Epic**: Observability / FinOps
**Estimate**: 1 day

## Description
Implement a cost-effective log retention strategy by offloading older logs to MinIO (S3-compatible object storage) and providing a TUI-based mechanism to "rehydrate" (restore) them for auditing.

## Directives
1.  **Snapshot Repository**: Configure Elasticsearch to use MinIO as a Snapshot Repository.
2.  **ILM Policy**: Define an Index Lifecycle Management policy:
    - **Hot**: 7 days (kept in cluster).
    - **Delete/Archive**: Snapshot to MinIO after 7 days, then delete indices.
3.  **TUI Integration**:
    - **Archive Status**: View snapshot status.
    - **Rehydrate**: Select a date range/snapshot to restore into a temporary "Cold" node or existing node for analysis.
    - **Prune**: Manually trigger snapshots/deletion.

## Goal
reduce storage costs on the OCI Block Volumes while satisfying long-term retention/audit requirements.
