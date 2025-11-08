# OCI Kubernetes Cluster Setup

This directory contains scripts for setting up and managing a Kubernetes cluster on Oracle Cloud Infrastructure (OCI) with enhanced storage provisioner management.

## Quick Start

```bash
# Setup cluster with Longhorn (default)
./setup_k8s_cluster.sh

# Setup cluster with Local Path Provisioner
STORAGE_PROVISIONER=local-path ./setup_k8s_cluster.sh

# Deploy components
./deploy_components.sh
```

## Features

- **Automated K8s Installation**: Full cluster setup with Cilium CNI
- **Smart Storage Management**: Automatic detection, migration, and updates for storage provisioners
- **Dashboard**: Kubernetes Dashboard with auto-tunneling
- **Metrics**: Metrics server for resource monitoring
- **Ingress**: NGINX Ingress Controller

## Storage Provisioner Management

The cluster setup now includes intelligent storage provisioner management:

✨ **Automatic Detection**: Identifies installed storage provisioners
✨ **Safe Migration**: Migrates PVCs between storage classes
✨ **Version Management**: Checks for updates and upgrades with automatic rollback
✨ **Resource Optimization**: Automatically removes unused provisioners

See [STORAGE_PROVISIONER.md](./STORAGE_PROVISIONER.md) for detailed documentation.

## Scripts

### setup_k8s_cluster.sh
Main cluster setup script with comprehensive storage provisioner management.

**Environment Variables**:
- `STORAGE_PROVISIONER`: Choose storage provisioner (`longhorn` or `local-path`)
- `CILIUM_MODE`: CNI mode (`vxlan` or `direct`)
- `ENABLE_DASHBOARD`: Enable Kubernetes Dashboard (default: `true`)
- `ENABLE_INGRESS`: Enable NGINX Ingress (default: `true`)
- `K8S_VERSION`: Kubernetes version (default: `1.34.1`)

**Example**:
```bash
STORAGE_PROVISIONER=longhorn CILIUM_MODE=vxlan ./setup_k8s_cluster.sh
```

### deploy_components.sh
Deploy application components (postgres, minio, nexus) to the cluster.

**Usage**:
```bash
# Interactive selection
./deploy_components.sh

# Deploy specific components
./deploy_components.sh postgres minio
```

### test_storage_provisioner.sh
Test script for validating storage provisioner functions.

**Usage**:
```bash
./test_storage_provisioner.sh
```

### connect_oci_cluster.sh
Connect to the OCI cluster and setup local kubeconfig.

## Common Tasks

### Switch Storage Provisioners

```bash
# From local-path to longhorn
STORAGE_PROVISIONER=longhorn ./setup_k8s_cluster.sh

# The script will:
# 1. Detect current provisioner
# 2. Install new provisioner
# 3. Migrate PVCs
# 4. Remove old provisioner
```

### Update Storage Provisioner

```bash
# Updates are automatic when running setup
./setup_k8s_cluster.sh

# The script checks for updates and upgrades if available
```

### Check Cluster Status

```bash
kubectl get nodes
kubectl get pods --all-namespaces
kubectl get pvc --all-namespaces
```

### Access Dashboard

The dashboard is automatically tunneled on port 8443:

```bash
# Get the token
kubectl -n kubernetes-dashboard create token admin-user --duration=24h

# Access at: https://localhost:8443
```

## Troubleshooting

### Migration Issues

If PVC migration fails, check for annotations:

```bash
kubectl get pvc --all-namespaces -o json | \
  jq -r '.items[] | select(.metadata.annotations["migration.manual.required"]=="true") | 
  "\(.metadata.namespace)/\(.metadata.name)"'
```

See [STORAGE_PROVISIONER.md](./STORAGE_PROVISIONER.md#manual-migration-for-bound-pvcs) for manual migration steps.

### Provisioner Health

```bash
# Check Longhorn
kubectl -n longhorn-system get pods
kubectl -n longhorn-system get deploy

# Check Local Path Provisioner
kubectl -n local-path-storage get pods
kubectl -n local-path-storage get deploy
```

### View Logs

```bash
# Setup logs
ls -lh ../logs/

# Longhorn logs
kubectl -n longhorn-system logs -l app=longhorn-manager

# Local Path Provisioner logs
kubectl -n local-path-storage logs -l app=local-path-provisioner
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│           OCI K8s Cluster (Cilium CNI)              │
├─────────────────────────────────────────────────────┤
│  Master Node                                        │
│    - API Server (6443)                              │
│    - Cilium CNI                                     │
│    - Storage Provisioner (Longhorn or Local Path)  │
│    - Kubernetes Dashboard                           │
│    - NGINX Ingress Controller                       │
│    - Metrics Server                                 │
├─────────────────────────────────────────────────────┤
│  Worker Nodes                                       │
│    - Cilium Agents                                  │
│    - Storage Provisioner Agents                     │
│    - Application Pods                               │
└─────────────────────────────────────────────────────┘
```

## Storage Classes

### Longhorn (Default)
- **Type**: Distributed block storage
- **Replication**: Multi-node
- **Best for**: Production, high availability
- **UI**: Port-forward to `longhorn-frontend:80`

### Local Path Provisioner
- **Type**: Local host path storage
- **Replication**: None
- **Best for**: Development, single-node
- **Lightweight**: Minimal resource usage

## Components

Application components are stored in `../components/`:

- **postgres**: PostgreSQL database with dynamic PVC
- **minio**: Object storage (S3-compatible)
- **nexus**: Artifact repository manager

Each component includes:
- Kubernetes manifests
- Optional `commands.sh` for custom deployment logic

## Best Practices

1. **Always backup data** before switching storage provisioners
2. **Test in development** before production changes
3. **Monitor resource usage** - Longhorn requires more resources
4. **Keep provisioners updated** by running setup periodically
5. **Use appropriate storage class** for your workload

## Advanced Configuration

### Custom Longhorn Settings

```bash
# Access Longhorn UI
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80

# Configure via UI at http://localhost:8080
```

### Custom Local Path Directory

```bash
# Edit ConfigMap
kubectl -n local-path-storage edit configmap local-path-config

# Update the path configuration
```

## References

- [STORAGE_PROVISIONER.md](./STORAGE_PROVISIONER.md) - Detailed storage documentation
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Cilium Documentation](https://docs.cilium.io/)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Local Path Provisioner](https://github.com/rancher/local-path-provisioner)
