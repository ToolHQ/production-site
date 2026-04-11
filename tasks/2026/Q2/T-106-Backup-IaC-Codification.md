# T-106: Backup Infrastructure Codification (IaC Gap)

**Status**: [ ] To Do | **Priority**: 🔼 High | **Owner**: Infra | **Est**: 1h

## 🎯 Objective
The Longhorn backup pipeline (Longhorn → MinIO → Google Drive) is **fully operational** but
two critical resources exist **only in the live cluster**, not in the Git repository. This is
configuration drift discovered during the T-104 audit (2026-04-11). If the cluster were
rebuilt or Longhorn reinstalled, the backup pipeline would silently break.

## 🔍 Problem Analysis

### What's missing from Git

| Resource | Namespace | Live Value | In Repo? |
|---|---|---|---|
| `BackupTarget` CRD instance (`default`) | `longhorn-system` | `s3://k8s-backups@us-east-1/`, credentialSecret=`minio-secret` | ❌ |
| `Secret/minio-secret` (S3 credentials) | `longhorn-system` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINTS` | ❌ |

### What IS versioned (and working)

| Resource | Path | Status |
|---|---|---|
| RecurringJob `backup-daily` | `components/backup/longhorn-recurring-job.yaml` | ✅ |
| MinIO Deployment + Secret | `components/minio/minio-resources.yaml` | ✅ |
| Etcd Backup CronJob | `components/backup/etcd-backup-cronjob.yaml` | ✅ (suspended) |
| Postgres Snapshot CronJob | `components/backup/snapshot-cronjob.yaml` | ✅ |
| rclone sync script | `oci-k8s-cluster/scripts/cloud_ops/sync_to_gdrive.sh` | ✅ |
| TUI Backup Menu (option 5) | `oci-k8s-cluster/k8s_ops_menu.sh:2583-2606` | ✅ |

### Why this was missed
The TUI (`k8s_ops_menu.sh`, option 5 in Backup Menu) creates the secret and patches the
BackupTarget interactively via `kubectl create secret --dry-run | kubectl apply` and
`kubectl patch`. This is correct for initial setup, but produces no artifact in Git.
The Longhorn CRD definition (`components/longhorn/longhorn.yaml`) contains the `BackupTarget`
schema (CRD) but not an instance. The secret in `longhorn-system` uses different keys than
the MinIO root secret in `minio` namespace — it has dedicated S3 access keys.

## 📋 Execution Plan

### Phase 1: Create declarative manifests in `components/backup/`

- [ ] Create `components/backup/longhorn-backup-target.yaml`:
  ```yaml
  apiVersion: longhorn.io/v1beta2
  kind: BackupTarget
  metadata:
    name: default
    namespace: longhorn-system
  spec:
    backupTargetURL: s3://k8s-backups@us-east-1/
    credentialSecret: minio-secret
    pollInterval: 5m0s
  ```
- [ ] Create `components/backup/longhorn-backup-secret.yaml` as a **template** (no real values):
  ```yaml
  # TEMPLATE — Do NOT commit real credentials.
  # Real secret is created via TUI (Backup Menu > Option 5) or commands.sh.
  # Required keys: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ENDPOINTS
  # Endpoint: http://minio-service.minio.svc.cluster.local:9000
  apiVersion: v1
  kind: Secret
  metadata:
    name: minio-secret
    namespace: longhorn-system
  type: Opaque
  stringData:
    AWS_ACCESS_KEY_ID: "<REPLACE: MinIO access key>"
    AWS_SECRET_ACCESS_KEY: "<REPLACE: MinIO secret key>"
    AWS_ENDPOINTS: "http://minio-service.minio.svc.cluster.local:9000"
  ```

### Phase 2: Create `components/backup/commands.sh`

- [ ] Create `components/backup/commands.sh` following the project pattern:
  - Apply `longhorn-recurring-job.yaml` (already exists)
  - Apply `longhorn-backup-target.yaml` (new)
  - Apply `snapshot-automation-rbac.yaml` + `snapshot-cronjob.yaml` (already exist)
  - Print warning if `minio-secret` doesn't exist in `longhorn-system` (direct user to TUI)
  - Do NOT auto-apply the secret template (contains placeholders)

### Phase 3: Align TUI reference

- [ ] In TUI option 5 (Configure Backup Target), after applying secret+patch, add a
  comment/echo pointing to `components/backup/longhorn-backup-target.yaml` as the source
  of truth for the URL, so future developers know it exists in Git.

### Phase 4: Verify idempotency

- [ ] Run `components/backup/commands.sh` against live cluster — expect all resources
  already exist, no changes, no errors.
- [ ] Confirm `backup-daily` continues to produce `Completed` backups after the apply.

## ✅ Definition of Done
- [ ] `components/backup/longhorn-backup-target.yaml` versioned in Git
- [ ] `components/backup/longhorn-backup-secret.yaml` template versioned (no real credentials)
- [ ] `components/backup/commands.sh` created, applies all backup manifests idempotently
- [ ] TUI option 5 references the declarative manifest
- [ ] Live cluster unaffected (no backup disruption)

## 🔗 Context
- Discovered during T-104 audit (2026-04-11) — pipeline was operational but not codified
- TUI already handles interactive setup (`k8s_ops_menu.sh:2583-2606`)
- Secret uses dedicated MinIO S3 access keys (not root creds) — created in MinIO console
- Zero Variable Cost policy: MinIO in-cluster + Google Drive, no OCI Object Storage
- Related: T-104 (Replica Integrity), T-101 (Storage Strategy Pivot), T-102 (Watchdog)
