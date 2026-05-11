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

| Volume / scope                    | Criticality   | Producer / group                                      | MinIO retention                                | GDrive retention    | Notes                                                                                                        |
| --------------------------------- | ------------- | ----------------------------------------------------- | ---------------------------------------------- | ------------------- | ------------------------------------------------------------------------------------------------------------ |
| `postgres-data-postgres-0`        | Critical      | `backup-daily` / `default` + `postgres-auto-snapshot` | 7 daily backups + 7 backup-backed 6h snapshots | Append-only archive | Primary gets the densest restore window; a live count of 14 backups is expected under this policy.           |
| `postgres-data-postgres-1`        | Critical      | `backup-daily` / `default`                            | 7 daily backups                                | Append-only archive | Replica keeps daily protection only.                                                                         |
| `nexus-pvc`                       | Critical      | `backup-daily` / `default`                            | 7 daily backups                                | Append-only archive | Internal registry state.                                                                                     |
| `coroot-data`                     | Observability | `backup-observability-daily` / `observability`        | 1 daily backup                                 | Append-only archive | Regenerable observability data under the current rootfs pressure budget.                                     |
| `coroot-prometheus-server`        | Observability | `backup-observability-daily` / `observability`        | 1 daily backup                                 | Append-only archive | Lower restore priority than core services.                                                                   |
| `data-coroot-clickhouse-shard0-0` | Observability | `backup-observability-daily` / `observability`        | 1 daily backup                                 | Append-only archive | Lower restore priority than core services.                                                                   |
| `kubecost-prometheus-server`      | Low           | `backup-observability-daily` / `observability`        | 1 daily backup                                 | Append-only archive | Cost telemetry is non-critical.                                                                              |
| `kubecost-cost-analyzer`          | Low           | `backup-observability-daily` / `observability`        | 1 daily backup                                 | Append-only archive | Cost telemetry is non-critical.                                                                              |
| `etcd`                            | Control plane | `etcd-backup`                                         | 4 MinIO snapshots (~24h) + 4 local staged      | 30 cloud days       | Separate file-based pipeline; active again, uploaded via S3 API, and synced offsite from `/var/backup/etcd`. |

## Operational notes

- Do not prune `backupstore/` by file age. Longhorn backupstore is block-deduplicated and requires Longhorn-aware cleanup.
- The offsite copy is intentionally append-only for Longhorn data. Retention reduction happens at the MinIO generation layer by assigning the correct recurring job group per PVC.
- The MinIO bucket `nexus/` is active Nexus blob-store data, not backup payload. Keep bucket expiration disabled and manage any future retention from Nexus itself, never by deleting MinIO objects directly.
- ETCD offsite sync must read snapshots from `/var/backup/etcd`, not from `/data/minio/k8s-backups/etcd`.
- The `etcd-backup` upload step is responsible for pruning the MinIO `k8s-backups/etcd/` prefix to the four newest `etcd-*.db` objects and deleting legacy `*.db.part` / probe artifacts.
- Legacy ETCD artifacts written directly into the MinIO backend filesystem may survive outside the S3 API view. If `mc ls` no longer shows them but they still exist under `/data/minio/k8s-backups/etcd/`, treat them as one-off backend garbage and remove them explicitly on the master after validating the four retained snapshots.
- On 2026-04-18 the master hit `DiskPressure=True` with `/var/backup` at `2.1G`; the ETCD CronJob was hardened to keep only the four newest local snapshots so the staging area does not keep growing on the root filesystem.
- Legacy GDrive entries created by copying the MinIO backend directly can appear as bogus directories containing `xl.meta`. The directed ETCD cleanup pass was executed on `2026-04-18`; the remote now holds `9` valid snapshots / `2.237 GiB`.
- The three obsolete postgres manual `VolumeSnapshot` objects from Dec/2025 were deleted on `2026-04-19`; their `VolumeSnapshotContent` objects disappeared immediately because the class uses `deletionPolicy: Delete`.
- The stale `BackupVolume` cleanup pass removed the historical payload, but Longhorn backup-target sync may recreate empty `BackupVolume` CRs with blank `lastBackupName` / `size` from residual backend metadata. Treat those as control-plane residue unless they regain stored bytes or live backup references.
- Longhorn may release the underlying backupstore payload asynchronously after the CR deletions, so storage reclaim is expected to lag the inventory cleanup.
- Current measured MinIO usage on `2026-04-19` after the retention cleanup: `k8s-backups = 8055 MiB`, split as `backupstore = 7036 MiB` and `etcd = 1019 MiB`; the `< 8 GiB` target is satisfied for the full bucket.
- Current measured Nexus blob-store usage on `2026-04-19`: bucket `nexus = 4.3 GiB / 3908 objects`; treat this as live registry/package state, not as generic MinIO backlog.
- Current measured ETCD GDrive cleanup impact on 2026-04-18: `~1.24 GiB` of legacy directory garbage plus one duplicate `254.52 MiB` snapshot; cleanup already applied and revalidated.

See `docs/backup-policy.md` for the consolidated policy, including the Nexus bucket decision.

## Apply

```bash
kubectl apply -f components/backup/longhorn-recurring-job.yaml
kubectl apply -f components/backup/longhorn-recurring-job-observability.yaml
kubectl apply -f components/backup/longhorn-backup-target.yaml
kubectl apply -f components/backup/etcd-backup-cronjob.yaml
kubectl apply -f components/backup/snapshot-automation-rbac.yaml
kubectl apply -f components/backup/snapshot-cronjob.yaml
```

`components/backup/etcd-backup-cronjob.yaml` is the ETCD source of truth and contains both
`CronJob/etcd-backup` and `CronJob/etcd-backup-prune`.

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

Audit stale Longhorn backup generations:

```bash
components/backup/cleanup-longhorn-stale-backupvolumes.sh
```

Audit legacy ETCD artifacts in Google Drive:

```bash
oci-k8s-cluster/scripts/cloud_ops/cleanup_gdrive_etcd_legacy.sh
```
