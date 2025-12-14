#!/bin/bash
# scripts/observability/install_deepflow.sh
# Installs DeepFlow (eBPF Observability) via Helm
# Optimized for OCI Ampere (ARM64) - ULTRA MINIMAL & INTERACTIVE

set -euo pipefail
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../../common.sh"
source "$SCRIPT_DIR/../../lib/credstore.sh"

echo "🕵️  Initializing DeepFlow Installation (Minimal Mode)..."

# 1. Add Helm Repo
echo "📦 Adding DeepFlow Helm repository..."
ssh oci-k8s-master "helm repo add deepflow https://deepflowio.github.io/deepflow && helm repo update"

# 2. Check for Namespace
if ! ssh oci-k8s-master "kubectl get ns deepflow >/dev/null 2>&1"; then
    echo "Creating 'deepflow' namespace..."
    ssh oci-k8s-master "kubectl create ns deepflow"
fi

# 3. Create Custom Values Config for OCI
# Tuned for Minimal Resource Usage & Slow Startup
echo "✍️  Generating DeepFlow OCI config..."
cat <<EOF > /tmp/deepflow-values.yaml
global:
  allInOne: true 
  image:
    repository: deepflowce
    pullPolicy: IfNotPresent
  
  replicas: 1

deployComponent:
  ingress: true
  grafana: true

# DeepFlow Server Configuration
deepflow-server:
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      memory: 1Gi
  
  # Slow startup on ARM64/Low Resource (MySQL Migration)
  readinessProbe:
    initialDelaySeconds: 120
    periodSeconds: 10
  livenessProbe:
    initialDelaySeconds: 120
    periodSeconds: 20

# Grafana Configuration (Fixes startup loop)
grafana:
  readinessProbe:
    initialDelaySeconds: 60
    periodSeconds: 10
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - deepflow.dnor.io
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"

# Database (ClickHouse) Tuning - ULTRA MINIMAL
clickhouse:
  replicas: 1
  resources:
    requests:
      memory: 256Mi
    limits:
      memory: 1Gi
  
  clickhouse:
    maxMemoryUsage: 536870912 # 512MB
    backgroudPoolSize: 2

  # Disk Usage (To match cluster standards ~1-5GB)
  storageConfig:
    persistence:
      - name: clickhouse-path
        accessModes: [ "ReadWriteOnce" ]
        size: 5Gi  # Data
        storageClass: "longhorn"
      - name: clickhouse-storage-path
        accessModes: [ "ReadWriteOnce" ]
        size: 1Gi  # Logs/Temp
        storageClass: "longhorn"

# Metadata Database (MySQL) Tuning
mysql:
  resources:
    requests:
      memory: 128Mi
    limits:
      memory: 512Mi
  storageConfig:
    persistence:
      size: 2Gi
      storageClass: "longhorn"

# Agent (DaemonSet)
deepflow-agent:
  resources:
    requests:
      cpu: 20m
      memory: 64Mi
    limits:
      memory: 256Mi
EOF

# Transfer values to master
scp_to_remote oci-k8s-master /tmp/deepflow-values.yaml /home/ubuntu/deepflow-values.yaml

# 4. Uninstall if exists (Mandatory for resizing PVCs down)
if ssh oci-k8s-master "helm status deepflow -n deepflow >/dev/null 2>&1"; then
    echo "⚠️  DeepFlow release exists. Checking config..."
    # We do NOT force uninstall here anymore to avoid losing data if user is just updating.
    # But if PVC sizes changed, manual intervention is needed.
    # For now, we assume this script is for fresh installs or updates.
fi

# 5. Install/Upgrade (NO WAIT - for TUI responsiveness)
echo "🚀 Deploying DeepFlow (v6.6.018)..."
ssh oci-k8s-master "helm upgrade --install deepflow deepflow/deepflow -n deepflow -f /home/ubuntu/deepflow-values.yaml --version 6.6.018 --timeout 10m"

# 6. Interactive Watch (Replacing --wait)
echo "✅ Deployment triggered!"
echo ""
echo -e "\033[1;33m📡 Watching Pod Status... (Press Ctrl+C to stop watching and return to menu)\033[0m"
echo "   Note: 'CrashLoopBackOff' is normal during first minute (DB init)."
echo ""

# Trap Ctrl+C to exit gracefully
trap "echo -e '\n\n✅ Installation finished (in background). Returned to menu.'; exit 0" SIGINT

# Watch loop
ssh -t oci-k8s-master "watch --color -n 2 'kubectl get pods -n deepflow -o wide'"

echo "✅ DeepFlow deployed! Access at https://deepflow.dnor.io"

# 7. Register Credentials
echo "🔑 Registering credentials in Credential Manager..."
if command -v credstore_add >/dev/null 2>&1; then
    credstore_add "deepflow-console" "admin" "deepflow" "DeepFlow Console Admin (Default)"
    credstore_add "deepflow-grafana" "admin" "deepflow" "DeepFlow Grafana Admin (Default)"
    credstore_add "deepflow-mysql" "root" "deepflow" "DeepFlow MySQL Root"
    echo "✓ Credentials registered"
else
    # Fallback if function not exported (should not happen if source common.sh)
    echo "⚠️  Credential Manager not available. Skipping registration."
fi
