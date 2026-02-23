# Goal Description
The current Longhorn Backup strategy is overly aggressive for a resource-constrained "Zero-Waste" environment. By scheduling `hourly`, `4h`, and `daily` local snapshots, Longhorn is retaining up to 25 full snapshots per volume. This is consuming nearly 100% of the nodes' logical storage limits, triggering Longhorn to mark the nodes as `Schedulable: 0 Bi` to protect the host OS disk.

The objective is to **transition to a Remote-First Backup Strategy**. We will rely entirely on the established Minio -> Google Drive pipeline for disaster recovery, keeping the local Kubernetes nodes lean and strictly for active workloads.

## Proposed Changes

1. **Delete Aggressive Local Policies:**
   - Remove the `snapshot-hourly` CronJob/RecurringJob.
   - Remove the `snapshot-4h` CronJob/RecurringJob.
   - Keep only `backup-daily` (which exports to remote Minio/GDrive) and `maintenance-cleanup`.

2. **Adjust Daily Backup Retention:**
   - Modify the `backup-daily` job to retain strictly **3 to 7 backups remotely** (instead of 14), and **1 local snapshot** (only the active head).
   - *Rationale:* Since the backups are synchronized to Google Drive off-cluster by the `sync_to_gdrive.sh` script, hoarding 14 days locally in Minio/Longhorn is redundant.

3. **Execute Cluster-Wide Snapshot Purge (Immediate Relief):**
   - Run a script or use Longhorn UI/API to manually delete all historical snapshots (`snapshot-xxx`) for all 12 active volumes.
   - Wait for the Longhorn `snapshot-purge` engine to free up the physical space on `/var/lib/longhorn`.
   - *Expected Result:* Disk usage on `k8s-node-1/2/3` should drop significantly, and the Longhorn Dashboard will return to green (`Schedulable > 0`).

## Verification Plan

### Automated/System Verification
1. **Longhorn API/CLI Check:**
   - Run `kubectl get recurringjobs -n longhorn-system` to verify only the approved policies (`backup-daily`, `maintenance-cleanup`) remain.
2. **Space Reclamation Check:**
   - Run the Inventory Report (`./generate_inventory_report.sh`). The `Snap` column for all nodes should drop from `929M/15G` to near zero.
3. **TUI Validation:**
   - The user will check the Longhorn Web UI Dashboard. The "Storage Schedulable" dial should reflect the reclaimed space (e.g., jump from 0 Bi to ~15-20 Gi per node).

### User Action Required
- Review and approve the strategy to drop intraday (hourly/4h) local snapshots in favor of a single daily remote backup.
- Approval to execute the irreversible **Purge** of historical local snapshots to rescue the cluster's storage bounds.


## Status
- **Status**:   Done

