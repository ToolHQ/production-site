# AI Context: OCI K8s Cluster

> [!IMPORTANT]
> This file is optimized for AI Agents to quickly grasp the cluster state, architecture, and operational constraints.

## Identity & Purpose
- **Project**: OCI Free Tier Kubernetes Cluster (ARM64/Aussie).
- **Core Function**: Hosting personal production services (Postgres, Minio, Nexus, ECK).
- **Key Constraint**: Running on Oracle Cloud Free Tier (4 OCPU, 24GB RAM total). Resource efficiency is paramount.

## Architecture
- **Master**: `oci-k8s-master` (150.136.34.254) - Control Plane + Worker.
- **Workers**: `oci-k8s-node-1`, `oci-k8s-node-2`, `oci-k8s-node-3` (ARM64).
- **Kubernetes Version**: v1.34.2
- **CNI**: Cilium (VXLAN mode).

### 3. Access & Networking
- **Ingress-First Policy**: ALL interactive services (Kibana, Grafana, Nexus, etc) MUST be exposed via `ingress-nginx` with a `*.dnor.io` subdomain.
- **No-SaaS Policy**: We prioritized Self-Hosted solutions. Do NOT implement SaaS-based monitoring (e.g., Pixie Cloud, Grafana Cloud) unless explicitly authorized. Data must stay in the cluster.
- **TUI Integration**: The `k8s_ops_menu.sh` relies on these Ingress routes for its "One-Click Open" functionality.
- **Tunneling**: Access is achieved via SSH Tunnel to 443 (Ingress) or direct NodePort.

- **Storage**:
    - **Longhorn** (Default): Distributed block storage.
    - **Local Path**: Lightweight alternative for extensive I/O.
- **Ingress**: NGINX Ingress Controller.

## Key Locations
- **Root**: `/home/ToolHQ/production-site/oci-k8s-cluster`
- **TUI**: `k8s_ops_menu.sh` (Main entry point for operations).
- **Components**: `../components/` (Helm charts/Manifests for apps).
- **Docs**: `./docs/` (This folder).

## Operational Knowledge
### Connectivity
- Access requires SSH Tunnel to Master on port 6443.
- `kubectl` needs `insecure-skip-tls-verify: true` when tunneling to `127.0.0.1`.

### Critical Scripts
- `setup_k8s_cluster.sh`: Idempotent cluster setup/repair.
- `full_cluster_heal.sh`: "Nuke it from orbit" repair script.
- `safe_node_update.sh`: Cordon/Drain/Update workflow.

### Common Issues
- **Storage Migration**: Switching between Longhorn/Local-Path requires valid migration annotations.
- **Certificates**: Kubeadm certs auto-renew, but check if connection fails.

## Roadmap Status
See [ROADMAP.md](./ROADMAP.md) for active development tasks.
