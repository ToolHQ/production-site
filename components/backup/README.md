# Backup Policy

## Findings from T-127 (2026-04-15)

- The offsite sync runs on the master as `gdrive-sync.timer`, not as a Kubernetes CronJob.
- The previous offsite routine used `rclone sync` against the full `k8s-backups` tree, so Google Drive behaved as a near-mirror of MinIO instead of a longer-lived archive.
- The live sync log showed `directory not found` races while Longhorn was mutating `backupstore`, then succeeded on retry. That makes destructive mirroring a poor fit for the Longhorn object layout.
- `backup-daily` is currently respected for active `nexus`, `coroot` and `kubecost` volumes.
- Historical over-retention comes from two sources:
  - stale `BackupVolume` generations from older PVC incarnations dated mostly Dec/2025 -> Jan/2026;
  - `postgres-auto-snapshot`, whose `VolumeSnapshotContent` handles use `bak://...` and create extra Longhorn backups every 6 hours for `postgres-data-postgres-0`.

## Target policy

| Volume / scope | Criticality | Producer / group | MinIO retention | GDrive retention | Notes |
| --- | --- | --- | --- | --- | --- |
| `postgres-data-postgres-0` | Critical | `backup-daily` / `default` + `postgres-auto-snapshot` | 7 daily backups + 7 backup-backed 6h snapshots | Append-only archive | Primary gets the densest restore window. |
| `postgres-data-postgres-1` | Critical | `backup-daily` / `default` | 7 daily backups | Append-only archive | Replica keeps daily protection only. |
| `nexus-pvc` | Critical | `backup-daily` / `default` | 7 daily backups | Append-only archive | Internal registry state. |
| `coroot-data` | Observability | `backup-observability-daily` / `observability` | 3 daily backups | Append-only archive | Regenerable observability data. |
| `coroot-prometheus-server` | Observability | `backup-observability-daily` / `observability` | 3 daily backups | Append-only archive | Lower restore priority than core services. |
| `data-coroot-clickhouse-shard0-0` | Observability | `backup-observability-daily` / `observability` | 3 daily backups | Append-only archive | Lower restore priority than core services. |
| `kubecost-prometheus-server` | Low | `backup-observability-daily` / `observability` | 3 daily backups | Append-only archive | Cost telemetry is non-critical. |
| `kubecost-cost-analyzer` | Low | `backup-observability-daily` / `observability` | 3 daily backups | Append-only archive | Cost telemetry is non-critical. |
| `etcd` | Control plane | `etcd-backup` | 7 local days | 30 cloud days | Separate file-based pipeline; currently suspended and must be reactivated. |

## Operational notes

- Do not prune `backupstore/` by file age. Longhorn backupstore is block-deduplicated and requires Longhorn-aware cleanup.
- The offsite copy is intentionally append-only for Longhorn data. Retention reduction happens at the MinIO generation layer by assigning the correct recurring job group per PVC.
- Stale `BackupVolume` generations from old PVCs still need a manual cleanup pass after validation of their restore value.

## Apply

```bash
kubectl apply -f components/backup/longhorn-recurring-job.yaml
kubectl apply -f components/backup/longhorn-recurring-job-observability.yaml
kubectl apply -f components/backup/longhorn-backup-target.yaml
kubectl apply -f components/backup/snapshot-automation-rbac.yaml
kubectl apply -f components/backup/snapshot-cronjob.yaml
```

Dry-run the per-PVC policy:

```bash
components/backup/apply-volume-backup-policy.sh
```

Apply the per-PVC policy:

```bash
components/backup/apply-volume-backup-policy.sh --apply
```

Install the offsite sync on the master:

```bash
oci-k8s-cluster/scripts/cloud_ops/install_gdrive_sync.sh
```