#!/bin/bash
# apply_policy.sh
# Applies "Gold Standard" RecurringJobs for Longhorn and binds volumes to them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common.sh"
source "$SCRIPT_DIR/vm_utils.sh"

POLICY_NAME="gold-standard"

log "🛡️  Initializing Backup Policy Manager..."

# 1. Define the RecurringJobs (Snapshot + Backup)
# - Snapshot: Every 1h, Keep 5
# - Backup: Every day at 03:00, Keep 7
cat <<EOF > /tmp/longhorn_policy.yaml
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: snapshot-hourly
  namespace: longhorn-system
  labels:
    recurring-job-group.longhorn.io/gold-standard: "enabled"
spec:
  cron: "0 * * * *"
  task: "snapshot"
  groups: ["gold-standard"]
  retain: 5
  concurrency: 1
---
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: backup-daily
  namespace: longhorn-system
  labels:
    recurring-job-group.longhorn.io/gold-standard: "enabled"
spec:
  cron: "0 3 * * *"
  task: "backup"
  groups: ["gold-standard"]
  retain: 7
  concurrency: 1
EOF

# 2. Apply CRDs
log "📝 Applying RecurringJobs (Snapshot: 1h/5, Backup: 1d/7)..."
scp -q -o StrictHostKeyChecking=no /tmp/longhorn_policy.yaml oci-k8s-master:/tmp/longhorn_policy.yaml
ssh oci-k8s-master "kubectl apply -f /tmp/longhorn_policy.yaml"
rm /tmp/longhorn_policy.yaml

# 3. Bind Volumes to Policy
# In Longhorn, we bind volumes to a "RecurringJob Group" by adding a label to the Volume CRD.
# Label: recurring-job-group.longhorn.io/gold-standard=enabled

log "🔗 Binding ALL volumes to 'gold-standard' group..."
# Get all Longhorn Volumes
VOLUMES=$(ssh oci-k8s-master "kubectl get lhv -n longhorn-system -o jsonpath='{.items[*].metadata.name}'")

for vol in $VOLUMES; do
    log "   -> Processing $vol..."
    ssh oci-k8s-master "kubectl label lhv $vol -n longhorn-system recurring-job-group.longhorn.io/gold-standard=enabled --overwrite" >/dev/null
done

log "✅ Policy Applied Successfully!"
log "   All volumes will now auto-snapshot (1h) and auto-backup (Daily)."
