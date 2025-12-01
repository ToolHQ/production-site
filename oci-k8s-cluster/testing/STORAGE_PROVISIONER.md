# Storage Provisioner Management

## Overview

The OCI K8s cluster setup now includes comprehensive storage provisioner management that handles:

- **Automatic detection** of installed storage provisioners
- **Version checking** and updates with automatic rollback
- **Safe migration** of PVCs between storage classes
- **Automatic cleanup** of unused provisioners to save resources

## Supported Storage Provisioners

### 1. Longhorn (Default)
- **Type**: Distributed block storage with replication
- **Best for**: Production environments requiring high availability
- **Features**: 
  - Volume replication across nodes
  - Snapshots and backups
  - Volume expansion
  - Web UI for management
- **Resource requirements**: Higher (runs on all nodes)

### 2. Local Path Provisioner
- **Type**: Local host path-based storage
- **Best for**: Development environments and single-node setups
- **Features**:
  - Simple and lightweight
  - Fast I/O (no network overhead)
  - Low resource usage
- **Limitations**: No replication or high availability

## Usage

### Setting the Storage Provisioner

Use the `STORAGE_PROVISIONER` environment variable:

```bash
# Use Longhorn (default)
STORAGE_PROVISIONER=longhorn ./setup_k8s_cluster.sh

# Use Local Path Provisioner
STORAGE_PROVISIONER=local-path ./setup_k8s_cluster.sh
```

### What Happens During Setup

The setup script now performs intelligent storage provisioner management:

1. **Detection Phase**
   - Checks if any storage provisioner is already installed
   - Identifies the version of installed provisioner(s)

2. **Decision Phase**
   - If desired provisioner is already installed:
     - Checks for updates
     - Upgrades if newer version available
     - Verifies health
   - If different provisioner is installed:
     - Installs desired provisioner alongside existing one
     - Migrates PVCs to new storage class
     - Removes old provisioner after successful migration

3. **Cleanup Phase**
   - Verifies no PVCs are using the old storage class
   - Safely uninstalls unused provisioner
   - Saves resources

## Migration Process

### Automatic Migration

When switching storage provisioners, the script:

1. Annotates existing PVCs with target storage class
2. Attempts to update PVC storage class (works for unbound PVCs)
3. For bound PVCs, adds annotation `migration.manual.required=true`

### Manual Migration (for bound PVCs)

If automatic migration isn't possible, follow these steps:

```bash
# 1. Check which PVCs need manual migration
kubectl get pvc --all-namespaces -o json | \
  jq -r '.items[] | select(.metadata.annotations["migration.manual.required"]=="true") | 
  "\(.metadata.namespace)/\(.metadata.name)"'

# 2. For each PVC:
# a. Backup data
# b. Scale down the workload using it
kubectl -n <namespace> scale deploy/<deployment> --replicas=0

# c. Delete the PVC (this also deletes the PV)
kubectl -n <namespace> delete pvc <pvc-name>

# d. Recreate the PVC with new storage class
# Edit the PVC YAML to use the new storageClassName
kubectl apply -f <pvc-yaml>

# e. Restore data (if needed)
# f. Scale up the workload
kubectl -n <namespace> scale deploy/<deployment> --replicas=1
```

## Update Management

### Checking for Updates

Updates are automatically checked when you run the setup script. The current version is compared against:

- For Longhorn: `LONGHORN_VERSION` variable in `common.sh`
- For Local Path Provisioner: Latest version from upstream

### Automatic Rollback

If an update fails:

1. The script detects the failure
2. Automatically rolls back to the previous version
3. Reports the failure
4. Cluster remains stable

## Health Verification

The setup script verifies provisioner health by:

- Checking all pods are in Running state
- Verifying deployments are ready
- Ensuring no pods are in error states

## Troubleshooting

### Multiple Provisioners Detected

If both provisioners are installed:

```bash
# Check current status
kubectl get storageclass
kubectl get pvc --all-namespaces

# The script will automatically clean up the unused one
# after migrating all PVCs
```

### Migration Failed

If migration fails:

```bash
# Check for PVCs needing manual migration
kubectl get pvc --all-namespaces -o json | \
  jq -r '.items[] | select(.metadata.annotations["migration.manual.required"]=="true")'

# Follow manual migration steps above
```

### Uninstall Blocked

If uninstall is blocked due to PVCs:

```bash
# List PVCs blocking uninstall
kubectl get pvc --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.storageClassName=="<old-class>") | 
  "\(.metadata.namespace)/\(.metadata.name)"'

# Migrate or delete these PVCs first
```

## Testing

A test script is provided to verify the storage provisioner functions:

```bash
cd oci-k8s-cluster
./test_storage_provisioner.sh
```

This script requires `MASTER_NODE` to be set and performs:
- Detection tests
- Version checking
- PVC listing
- Health verification

## Component Storage Configuration

When deploying components, ensure they use the correct storage class:

### Example: Postgres (uses local-path)
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: postgres
spec:
  storageClassName: local-path  # or 'longhorn'
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

### Example: Longhorn configuration
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-pvc
  namespace: myapp
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
```

## Best Practices

1. **Always backup data** before migration
2. **Test in development** before production migration
3. **Monitor resource usage** - Longhorn uses more resources
4. **Use appropriate storage class** for your workload:
   - High availability needs → Longhorn
   - Single node / development → Local Path Provisioner
5. **Keep provisioners updated** by running setup script periodically
6. **Check logs** if migration fails: `kubectl -n <namespace> logs <pod>`

## Advanced Configuration

### Custom Longhorn Settings

After installation, configure Longhorn via its UI:

```bash
# Port forward to Longhorn UI
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80

# Access at http://localhost:8080
```

### Custom Local Path Directory

Edit the local-path-provisioner ConfigMap:

```bash
kubectl -n local-path-storage edit configmap local-path-config

# Change the path in the config:
# paths: /opt/local-path-provisioner  # or your custom path
```

## References

- [Longhorn Documentation](https://longhorn.io/docs/)
- [Local Path Provisioner](https://github.com/rancher/local-path-provisioner)
- [Kubernetes Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
