# T-017: TUI Volume Manager

**Status**: In Progress
**Priority**: 🔼 High
**Owner**: Infrastructure Team
**Estimated**: 1d
**Related**: T-016 (Storage Optimization)

## Objective
Create an interactive TUI-based volume manager in `k8s_ops_menu.sh` that allows safe PVC resizing (both expand and shrink) with zero data loss, using Longhorn snapshots for shrink operations.

## User Story
As a cluster operator, I want to manage PVC sizes interactively from the TUI, so I can optimize storage usage without risking data loss or needing to manually run kubectl commands.

## Requirements

### 1. Volume Listing View
Display all PVCs across namespaces with:
- Namespace
- PVC Name
- Allocated Size
- Actual Usage (from df)
- Usage %
- Status (Bound/Pending/etc)
- Storage Class
- Age

### 2. Interactive Resize Interface
When selecting a volume:
- **Expand**: Direct PVC patch (Kubernetes native)
- **Shrink**: Safe multi-step procedure:
  1. Create Longhorn snapshot
  2. Scale down workload (0 replicas)
  3. Delete old PVC
  4. Create new smaller PVC from snapshot
  5. Update deployment/statefulset manifest
  6. Scale up workload

### 3. UI Components
- **Horizontal slider**: Visual size selection
- **Text input**: Precise size entry (e.g., "2Gi", "500Mi")
- **Validation**: 
  - Min: Current usage + 20% headroom
  - Max: Longhorn available space
- **Confirmation prompt**: Show before/after, estimated downtime
- **Progress indicator**: Real-time status during resize

### 4. Safety Features
- **Pre-flight checks**:
  - Verify Longhorn snapshot capability
  - Check available cluster storage
  - Validate workload can be scaled down
- **Automatic snapshot**: Always create before shrink
- **Rollback capability**: Keep snapshot for 24h
- **Dry-run mode**: Show what would happen without executing

## Implementation Plan

### Phase 1: Backend Scripts
- [ ] `scripts/volume_manager/list_volumes.sh` - Collect PVC data
- [ ] `scripts/volume_manager/get_usage.sh` - Calculate actual usage via df
- [ ] `scripts/volume_manager/resize_expand.sh` - Handle expansion
- [ ] `scripts/volume_manager/resize_shrink.sh` - Handle shrink (snapshot-based)
- [ ] `scripts/volume_manager/validate_resize.sh` - Pre-flight checks

### Phase 2: TUI Integration
- [ ] Add "Manage Volumes" option to main menu
- [ ] Create volume list view with fzf
- [ ] Build resize interface with whiptail/dialog
- [ ] Implement slider component (ASCII-based)
- [ ] Add confirmation dialogs

### Phase 3: Testing & Documentation
- [ ] Test expand on non-critical volume
- [ ] Test shrink with snapshot restore
- [ ] Document procedure in `docs/VOLUME_MANAGEMENT.md`
- [ ] Add to `k8s_ops_menu.sh` help text

## Technical Design

### Shrink Procedure (Zero Data Loss)
```bash
# 1. Create snapshot
kubectl create volumesnapshot $PVC_NAME-pre-shrink \
  --source-pvc=$PVC_NAME \
  -n $NAMESPACE

# 2. Scale down workload
kubectl scale deployment/$DEPLOYMENT -n $NAMESPACE --replicas=0

# 3. Wait for pod termination
kubectl wait --for=delete pod -l app=$APP -n $NAMESPACE --timeout=60s

# 4. Delete old PVC
kubectl delete pvc $PVC_NAME -n $NAMESPACE

# 5. Create new smaller PVC from snapshot
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC_NAME
  namespace: $NAMESPACE
spec:
  storageClassName: longhorn
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: $NEW_SIZE
  dataSource:
    name: $PVC_NAME-pre-shrink
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

# 6. Update manifest (if needed)
# Edit deployment YAML to reference new PVC

# 7. Scale up workload
kubectl scale deployment/$DEPLOYMENT -n $NAMESPACE --replicas=1

# 8. Verify data integrity
kubectl exec -n $NAMESPACE $POD -- ls -lah /data
```

### UI Mockup (ASCII)
```
╔═══════════════════════════════════════════════════════════════════════╗
║                        VOLUME MANAGER                                 ║
╠═══════════════════════════════════════════════════════════════════════╣
║ Namespace: postgres                                                   ║
║ PVC: postgres-pvc                                                     ║
║ Current Size: 5Gi                                                     ║
║ Actual Usage: 100Mi (2%)                                              ║
║ Status: Bound                                                         ║
╠═══════════════════════════════════════════════════════════════════════╣
║ New Size:                                                             ║
║ [====|=====================================] 2Gi                       ║
║  Min: 200Mi (usage + 20%)    Max: 50Gi (cluster available)           ║
║                                                                       ║
║ Enter size: [2Gi____]                                                ║
╠═══════════════════════════════════════════════════════════════════════╣
║ Operation: SHRINK (5Gi → 2Gi)                                        ║
║ Method: Snapshot → Delete → Restore                                  ║
║ Estimated Downtime: ~2 minutes                                       ║
║ Data Loss Risk: NONE (snapshot-based)                                ║
╠═══════════════════════════════════════════════════════════════════════╣
║ [Proceed]  [Cancel]  [Dry Run]                                       ║
╚═══════════════════════════════════════════════════════════════════════╝
```

## Integration with T-016
The Volume Manager will be used to execute T-016 optimizations:
1. Run audit (already done)
2. For each over-provisioned volume:
   - Open Volume Manager
   - Select volume
   - Set recommended size
   - Execute shrink
3. Verify all volumes optimized

## Success Criteria
- [ ] Can list all PVCs with usage stats
- [ ] Can expand PVC without data loss
- [ ] Can shrink PVC without data loss (via snapshot)
- [ ] UI is intuitive and responsive
- [ ] All operations have confirmation prompts
- [ ] Dry-run mode works correctly
- [ ] Documentation is complete

## Risks & Mitigations
| Risk | Mitigation |
|------|------------|
| Snapshot fails | Pre-flight check for snapshot capability |
| Insufficient space for new volume | Validate available space before delete |
| Workload doesn't scale down | Add timeout and manual intervention option |
| Data corruption during restore | Always keep original snapshot for 24h |
| User error (wrong size) | Confirmation prompt with before/after comparison |

## References
- Longhorn Snapshot API
- Kubernetes VolumeSnapshot CRD
- `k8s_ops_menu.sh` existing patterns
