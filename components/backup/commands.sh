#!/bin/bash
set -euo pipefail
# Backup Infrastructure Deployment (T-106)
# Applies all backup-related manifests idempotently.
# Secret must be created separately (TUI Backup Menu > Option 5, or manually).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "💾 Deploying Backup Infrastructure..."

# 1. Longhorn Recurring Job (backup-daily)
echo "  - Applying RecurringJob (backup-daily)..."
kubectl apply -f longhorn-recurring-job.yaml

# 2. Longhorn Recurring Job (backup-observability-daily)
echo "  - Applying RecurringJob (backup-observability-daily)..."
kubectl apply -f longhorn-recurring-job-observability.yaml

# 3. Longhorn BackupTarget (MinIO S3)
echo "  - Applying BackupTarget (MinIO S3)..."
kubectl apply -f longhorn-backup-target.yaml

# 4. Postgres Snapshot RBAC
echo "  - Applying Snapshot RBAC..."
kubectl apply -f snapshot-automation-rbac.yaml

# 5. Postgres Snapshot CronJob
echo "  - Applying Snapshot CronJob..."
kubectl apply -f snapshot-cronjob.yaml

# 6. Verify minio-secret exists in longhorn-system
if kubectl get secret minio-secret -n longhorn-system &>/dev/null; then
    echo "  - ✅ minio-secret exists in longhorn-system"
else
    echo ""
    echo "  ⚠️  WARNING: minio-secret NOT FOUND in longhorn-system namespace."
    echo "     Longhorn backups will NOT work until the secret is created."
    echo ""
    echo "     Create it via TUI: Backup Menu > Option 5 (Configure Backup Target)"
    echo "     Or manually:"
    echo "       kubectl create secret generic minio-secret -n longhorn-system \\"
    echo "         --from-literal=AWS_ACCESS_KEY_ID=<key> \\"
    echo "         --from-literal=AWS_SECRET_ACCESS_KEY=<secret> \\"
    echo "         --from-literal=AWS_ENDPOINTS=http://minio-service.minio.svc.cluster.local:9000"
    echo ""
    echo "     See: components/backup/longhorn-backup-secret.template.yaml"
fi

echo "  - ℹ️  Per-PVC backup groups: components/backup/apply-volume-backup-policy.sh"
echo "  - ℹ️  Legacy Longhorn cleanup audit: components/backup/cleanup-longhorn-stale-backupvolumes.sh"
echo "  - ℹ️  Legacy GDrive ETCD cleanup: oci-k8s-cluster/scripts/cloud_ops/cleanup_gdrive_etcd_legacy.sh"
echo "  - ℹ️  Offsite archive install: oci-k8s-cluster/scripts/cloud_ops/install_gdrive_sync.sh"

echo "✅ Backup infrastructure deployed."
