# Backup Policy

Date: 2026-04-19

## Scope

This document consolidates the current backup and retention policy for the production cluster.
It covers both actual backup payloads and adjacent storage that must not be treated as generic
backup garbage.

Core rules:

- Longhorn `backupstore` cleanup must happen through Longhorn objects, never by deleting MinIO files.
- ETCD retention is enforced by the `etcd-backup` pipeline and off-site sync, not by ad-hoc bucket cleanup.
- The MinIO bucket `nexus/` is active Nexus blob-store storage, not a backup bucket. Do not prune it with `mc rm`, age-based MinIO lifecycle, or filesystem deletes.

## Live state validated on 2026-04-19

| Scope                     | Measured state            | Notes                                                                    |
| ------------------------- | ------------------------- | ------------------------------------------------------------------------ |
| `k8s-backups`             | `8055 MiB` total          | Below the `< 8 GiB` target for T-124.                                    |
| `k8s-backups/backupstore` | `7036 MiB`                | Longhorn backup payload after observability + postgres legacy cleanup.   |
| `k8s-backups/etcd`        | `1019 MiB`                | Exactly four retained ETCD snapshots.                                    |
| `nexus` bucket            | `4.3 GiB`, `3908` objects | Live Nexus S3 blob store; payload currently lives under `nexus/content`. |

## Retention matrix

| Scope                                       | Producer / owner                                                         | Backend                           | Target retention                                                                                  | Enforcement                 | Delete path                                       |
| ------------------------------------------- | ------------------------------------------------------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------- | --------------------------- | ------------------------------------------------- |
| `postgres-data-postgres-0`                  | Longhorn `backup-daily` + `postgres-auto-snapshot`                       | MinIO `k8s-backups/backupstore`   | `7` daily backups + `7` backup-backed 6h snapshots                                                | Live IaC + snapshot CronJob | Longhorn `Backup` / `VolumeSnapshot` objects only |
| `postgres-data-postgres-1`                  | Longhorn `backup-daily`                                                  | MinIO `k8s-backups/backupstore`   | `7` daily backups                                                                                 | Live IaC                    | Longhorn `Backup` objects only                    |
| `nexus-pvc`                                 | Longhorn `backup-daily`                                                  | MinIO `k8s-backups/backupstore`   | `7` daily backups                                                                                 | Live IaC                    | Longhorn `Backup` objects only                    |
| Observability PVCs (`coroot*`, `kubecost*`) | Longhorn `backup-observability-daily`                                    | MinIO `k8s-backups/backupstore`   | `3` daily backups                                                                                 | Live IaC                    | Longhorn `Backup` objects only                    |
| ETCD                                        | `etcd-backup` CronJob + `gdrive-sync`                                    | MinIO `k8s-backups/etcd` + GDrive | `4` MinIO snapshots, `4` local staged snapshots, `30` cloud days                                  | Live IaC                    | `etcd-backup` prune logic + GDrive prune          |
| Nexus blob store `minio` (`nexus/`)         | Nexus repositories (`docker-repo`, `npm-repo`, `npm-proxy`, `npm-group`) | MinIO bucket `nexus`              | No MinIO-side expiration; retain all hosted artifacts until an explicit Nexus cleanup rule exists | Documented policy only      | Nexus-native cleanup policies only                |

## Nexus policy

The `nexus` bucket is not part of Longhorn backup retention. It is the active S3 blob store created by
`oci-k8s-cluster/lib/nexus_init.sh` as blob store `minio`, backed by bucket `nexus` with bucket expiration disabled.

Current policy:

1. Keep MinIO bucket lifecycle disabled for `nexus`.
2. Do not delete objects directly from MinIO or from `/data/minio/nexus`.
3. Treat hosted repositories as stateful rollback material:
   - `docker-repo`: retain all published images until an explicit image promotion / rollback retention workflow exists.
   - `npm-repo`: retain all published internal package versions until an explicit package deprecation policy exists.
4. Treat `npm-proxy` as cache data that is eligible for future Nexus-native cleanup if storage pressure returns, but do not prune it directly at MinIO level.
5. Any future retention automation for Nexus must be implemented through Nexus cleanup policies or repository-level policy attachment, not through bucket/object expiry.

## Operational guidance

- If `k8s-backups` grows, audit Longhorn `Backup`, `BackupVolume`, and `VolumeSnapshot` objects first.
- If `nexus` grows, inspect Nexus repositories and blob-store usage first. The first safe optimization target is proxy cache policy inside Nexus, not MinIO bucket deletion.
- Empty `BackupVolume` CRs recreated by Longhorn backup-target sync do not automatically imply retained payload; validate `lastBackupName`, `size`, and actual bucket usage before treating them as storage regressions.

## References

- `components/backup/README.md`
- `components/backup/etcd-backup-cronjob.yaml`
- `components/backup/snapshot-cronjob.yaml`
- `components/backup/volume-backup-policy.csv`
- `oci-k8s-cluster/lib/nexus_init.sh`
- `tasks/2026/Q2/T-124-Backup-Retention-Audit-and-ETCD-Recovery.md`
