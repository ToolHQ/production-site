# T-127 Longhorn Cleanup Plan

Date: 2026-04-18

Approved destructive action for T-127: delete stale Longhorn `BackupVolume` custom resources that no longer map to any live Longhorn volume.

Validated impact:

- No live `volumes.longhorn.io` object exists for these candidates.
- Active ETCD and GDrive cleanup is already complete.
- Remaining storage recovery opportunity is limited to historical backup generations.

Resources to delete:

- `pvc-9457cf3d-b57a-4148-9935-922998049c99-669c56db`
- `pvc-6a1e78ec-ca37-4d2d-91ae-61eb15be0e3a-cba058d6`
- `pvc-527009d1-6f72-4e1d-91e7-7bf74a60bd09-588a301f`
- `pvc-07028b00-5d63-4112-84e9-126faee4f6ce-dcd6f095`
- `pvc-b48937cd-c9ee-40e1-ab42-ddc5b3130478-b15387c2`
- `pvc-70ca900b-bf13-4b79-9cc7-91e35dc06f71-6bbe5f97`
- `pvc-024bef7e-a0a8-49cc-8632-f8827260217c-a3992f3a`
- `pvc-76d32043-c899-4346-a276-c4ad0b20a030-18ed1d6e`
- `pvc-8849d366-6900-489d-94bd-88e17ef269f9-3864eddf`
- `pvc-587154bf-86a4-40d4-8339-f33a0e082fd5-f539450f`
- `pvc-c6f50016-a36d-410b-bc17-292f9e4ff805-91f2261f`

Expected result:

- `11` stale `BackupVolume` CRs removed.
- `88` inherited backups eligible for purge.
- Approximately `5.57 GiB` of stale backup payload released from the Longhorn target over time.

Execution result:

- Applied on 2026-04-18.
- Residual stale comparison returned empty.
- Longhorn inventory converged to `8` `BackupVolume` for `8` live volumes.

---

# T-124 Backup Retention Cleanup Plan

Date: 2026-04-19

Approved destructive action for T-124: prune historical backup artifacts that remain after the
policy split between `default` and `observability`, plus ETCD artifacts in the MinIO bucket that
are no longer within the intended retention window.

Validated impact:

- No StatefulSet, Deployment, PVC, PV, Namespace or CRD will be deleted.
- Live protection remains in place after cleanup:
  - `nexus` and `postgres` keep the `default` Longhorn policy.
  - `coroot` and `kubecost` keep the `observability` Longhorn policy.
  - ETCD keeps the four newest MinIO snapshots plus off-site archive in Google Drive.
- `gdrive-sync` already completed successfully on `2026-04-19`, so off-site freshness is restored
  before pruning local/archive backlog.

Execution order:

1. Run one manual Job from `cronjob/etcd-backup` so the newly applied MinIO prune logic executes
   through the same supported path as the scheduled CronJob.
2. Delete the oldest seven Longhorn backups for each observability volume, preserving the newest
   three backups per volume.
3. Delete stale Longhorn `BackupVolume` roots that no longer correspond to any live
   `volumes.longhorn.io` object.

Resources preserved explicitly:

- ETCD snapshots kept in MinIO:
  - `etcd-20260419-000006.db`
  - `etcd-20260419-060005.db`
  - `etcd-20260419-120005.db`
  - `etcd-20260419-180005.db`
- Longhorn backups kept for observability volumes:
  - `pvc-23ab203e-0288-4f12-abeb-7be61e641f5c`: `backup-95a1e9a9c5564f27`, `backup-636d6b6c9a0d4d02`, `backup-385feb05e01a42b2`
  - `pvc-2b52212e-ef1b-46eb-a71c-c5c4329a690a`: `backup-ed7c3e30bb174812`, `backup-b98bd7c1c339447f`, `backup-df77b06373a8405b`
  - `pvc-3a209369-57bb-43e3-a59a-49dbfefc20e2`: `backup-24a2746bceb84ac0`, `backup-7ce5731e15974fce`, `backup-0ba2e8dc91254688`
  - `pvc-76755523-f94e-4ab1-9074-1caf86f61f57`: `backup-fbadc5016c584ec9`, `backup-a023ac2581b24ace`, `backup-02f09dd8e5da40f2`
  - `pvc-efbe8d2c-21c1-48dc-9d6b-ad973754b32e`: `backup-b4659eeacefa4d8a`, `backup-9659aa45f55a4c99`, `backup-b38e43204c024e89`

Resources to delete:

## 1. ETCD MinIO keys to delete

Older valid snapshots outside the four-newest window:

- `etcd-20260415-161757.db`
- `etcd-20260415-162445.db`
- `etcd-20260415-162522.db`
- `etcd-20260415-163157.db`
- `etcd-20260415-164005.db`
- `etcd-20260415-164937.db`
- `etcd-20260415-180005.db`
- `etcd-20260416-000005.db`
- `etcd-20260416-060005.db`
- `etcd-20260416-120005.db`
- `etcd-20260416-180005.db`
- `etcd-20260417-000005.db`
- `etcd-20260418-180018.db`

Legacy artifacts to delete:

- `etcd-20260202-121829.db.part`
- `etcd-20260202-121830.db.part`
- `etcd-20260202-121833.db.part`
- `etcd-20260202-121842.db.part`
- `etcd-20260202-121844.db.part`
- `etcd-20260202-121859.db.part`
- `etcd-20260202-121902.db.part`
- `etcd-20260202-121909.db.part`
- `etcd-20260202-121911.db.part`
- `etcd-20260202-121912.db.part`
- `etcd-20260202-121918.db.part`
- `etcd-20260202-121919.db.part`
- `etcd-20260202-121922.db.part`
- `etcd-20260202-121924.db.part`
- `etcd-20260202-121925.db.part`
- `etcd-20260202-121926.db.part`
- `etcd-20260202-121928.db.part`
- `etcd-20260202-121930.db.part`
- `etcd-20260202-121937.db.part`
- `etcd-20260202-121940.db.part`
- `etcd-20260202-121949.db.part`
- `etcd-20260202-121950.db.part`
- `etcd-20260202-121951.db.part`
- `etcd-20260202-121953.db.part`
- `etcd-20260202-121954.db.part`
- `etcd-20260202-122016.db.part`
- `etcd-20260202-122026.db.part`
- `etcd-20260202-122124.db.part`
- `latest_snapshot`
- `perm-check-1776270602.txt`
- `test-write.txt`

## 2. Observability Longhorn backups to delete

### `pvc-23ab203e-0288-4f12-abeb-7be61e641f5c`

- `backup-77b9f2a8c7894f1c`
- `backup-af8df4d11c8748a6`
- `backup-b2b77e30c7674dde`
- `backup-21621bb6ceb845cf`
- `backup-8124ab4e5a904caa`
- `backup-66669e0d0f484771`
- `backup-52de49d216e14f7a`

### `pvc-2b52212e-ef1b-46eb-a71c-c5c4329a690a`

- `backup-eb8d44cbaf8d49f1`
- `backup-a49d689d2e6e4cdc`
- `backup-a414c6f0960b4a3a`
- `backup-a5eee089154f4580`
- `backup-3bd3576137724a03`
- `backup-c04298bb21e74aa0`
- `backup-4a7a2b3989c24912`

### `pvc-3a209369-57bb-43e3-a59a-49dbfefc20e2`

- `backup-98680f8c2f8247b5`
- `backup-9ebafa6014a5451d`
- `backup-994523c2ffb9465a`
- `backup-a66d34768e8a4cf7`
- `backup-408057b9e9e64d4d`
- `backup-b9a5b010699b4f12`
- `backup-3a358e42dbe5400c`

### `pvc-76755523-f94e-4ab1-9074-1caf86f61f57`

- `backup-bca03629df2a41df`
- `backup-bc39baa9acae45fb`
- `backup-1da0cc7f05014c1b`
- `backup-ed03627821b14d9f`
- `backup-d038be175a5741f4`
- `backup-008af664d96f4a76`
- `backup-57bdabe4e6474d13`

### `pvc-efbe8d2c-21c1-48dc-9d6b-ad973754b32e`

- `backup-d2f26ce52b7e4738`
- `backup-446822d2f102470f`
- `backup-9bffd8908d774b99`
- `backup-9dcb3a69e6a34ee7`
- `backup-8d899e0ebce748e1`
- `backup-2e83879e4ba44f4e`
- `backup-2a7a6cde1b2f487b`

## 3. Stale Longhorn BackupVolume roots to delete

Empty orphan roots:

- `pvc-024bef7e-a0a8-49cc-8632-f8827260217c-a3992f3a`
- `pvc-07028b00-5d63-4112-84e9-126faee4f6ce-dcd6f095`
- `pvc-527009d1-6f72-4e1d-91e7-7bf74a60bd09-588a301f`
- `pvc-587154bf-86a4-40d4-8339-f33a0e082fd5-f539450f`
- `pvc-6a1e78ec-ca37-4d2d-91ae-61eb15be0e3a-cba058d6`
- `pvc-70ca900b-bf13-4b79-9cc7-91e35dc06f71-6bbe5f97`
- `pvc-8849d366-6900-489d-94bd-88e17ef269f9-3864eddf`
- `pvc-9457cf3d-b57a-4148-9935-922998049c99-669c56db`
- `pvc-b48937cd-c9ee-40e1-ab42-ddc5b3130478-b15387c2`
- `pvc-c6f50016-a36d-410b-bc17-292f9e4ff805-91f2261f`

Non-empty orphan root and its backups:

- BackupVolume root: `pvc-76d32043-c899-4346-a276-c4ad0b20a030-18ed1d6e`
- Associated backups to delete first:
  - `backup-ea5c310a2cc64149`
  - `backup-d56db28030b2489d`
  - `backup-ef75cd3c2ad340f7`
  - `backup-4c62be37eb594944`
  - `backup-033e4ab513e645f0`
  - `backup-d15c3b17a5c340fb`

Expected result:

- ETCD MinIO prefix converges to the four newest snapshots only.
- Observability volumes converge immediately from `10` backups to `3` backups each.
- Stale Longhorn inventory drops from `11` orphan roots to `0`.
- The remaining `k8s-backups` footprint should shrink materially, though backend reclaim inside
  Longhorn may lag the CR deletions.

Execution result:

- ETCD backend converged to four retained snapshots:
  - `etcd-20260419-120005.db`
  - `etcd-20260419-180005.db`
  - `etcd-20260419-221343.db`
  - `etcd-20260419-221527.db`
- All five observability volumes converged to `3` backups each.
- The three obsolete postgres manual `VolumeSnapshot` objects were deleted safely:
  - `manual-20251201-090155`
  - `manual-20251201-091805`
  - `postgres-pvc-restored-snap-20251213-125934`
- Their bound `VolumeSnapshotContent` objects were garbage-collected immediately, and no `backups.longhorn.io`
  remained for the legacy volume handles.
- `postgres-data-postgres-0` was intentionally left at `14` backups after validation that the live count
  matches the current policy: `7` daily backups + `7` backup-backed `VolumeSnapshot` restores.
- Measured MinIO usage after the postgres cleanup pass:
  - `k8s-backups = 8055 MiB`
  - `backupstore = 7036 MiB`
  - `etcd = 1019 MiB`
- Nexus follow-up concluded without destructive cleanup:
  - bucket `nexus` was validated as the active Nexus S3 blob store (`~4.3 GiB`, `3908` objects)
  - policy codified as `no MinIO-side pruning`; any future retention must be enforced from Nexus cleanup policies
- The Longhorn payload converged to the active retained data set, but backup-target sync recreated `10`
  empty `BackupVolume` CRs with blank status fields from residual backend metadata. Treat them as metadata-only
  residue rather than active stored backups.

---

# T-132 Nexus Cleanup Policy Automation

Date: 2026-04-19

Validated live state:

- `docker-repo`, `npm-repo`, `npm-proxy`, and `npm-group` all currently expose `cleanup: null`.
- Built-in cleanup tasks already exist in the live Nexus task inventory:
  - `repository.cleanup`
  - `assetBlob.cleanup` for `docker`
  - `assetBlob.cleanup` for `npm`
- No compact-blob-store task was observed during the live API audit used for this pass.
- Swagger confirms repository `PUT` payloads support `cleanup.policyNames`, but does not expose cleanup-policy creation or task creation endpoints.
- The internal cleanup-policy resource `/service/rest/internal/cleanup-policies` is live and responds `200` for list/create/update/preview.
- Script API browse is enabled, but script create/update currently returns `410` (`Creating and updating scripts is disable`).

Execution outcome:

1. Added internal cleanup-policy helpers plus npm-proxy convenience wrappers in `oci-k8s-cluster/lib/nexus_init.sh`.
2. Committed fallback Groovy upsert script at `oci-k8s-cluster/scripts/registry/nexus_cleanup_policy_upsert.groovy`.
3. Created live policy `npm-proxy-unused-30d` with `criteriaLastDownloaded = 30`.
4. Attached `npm-proxy-unused-30d` to `npm-proxy`; live repo JSON now returns `cleanup.policyNames=["npm-proxy-unused-30d"]`.
5. Readback of the policy reports `inUseCount = 1`.
6. Preview endpoint returned `200` with an empty sample (`{"total":-1,"results":[]}`) at validation time.
7. Decision: do not add blob-store compaction yet; revisit only after a future cleanup run produces measurable soft-deleted blobs.
