#!/bin/bash
# scripts/observability/install_deepflow.sh
# Installs DeepFlow (eBPF Observability) via Helm
# Optimized for OCI Ampere (ARM64) - ULTRA MINIMAL & INTERACTIVE

set -euo pipefail
# Use unique variable to avoid polluting k8s_ops_menu.sh SCRIPT_DIR
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$INSTALL_DIR/../../common.sh"
source "$INSTALL_DIR/../../lib/credstore.sh"

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
  allInOne: false
  hostNetwork: true
  image:
    repository: deepflowce
    pullPolicy: IfNotPresent
  
  replicas: 1

deployComponent:
  ingress: true
  grafana: true

# DeepFlow Server Configuration
server:
  resources:
    requests:
      cpu: 200m
      memory: 512Mi
    limits:
      memory: 1Gi

  
  # Slow startup on ARM64/Low Resource (MySQL Migration)
  readinessProbe:
    initialDelaySeconds: 300
    periodSeconds: 10
  livenessProbe:
    initialDelaySeconds: 300
    periodSeconds: 20

# Force Controller IP to fix 127.0.0.1 advertising issue
configmap:
  server.yaml:
    controller:
      trisolaris:



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
    tls:
      - secretName: deepflow-grafana-tls
        hosts:
          - deepflow.dnor.io
    annotations:
      cert-manager.io/cluster-issuer: "dnor-ca-issuer"

# Database (ClickHouse) Tuning - ULTRA MINIMAL
clickhouse:
  replicas: 1
  resources:
    requests:
      memory: 256Mi
    limits:
      memory: 3Gi
  
  livenessProbe:
    initialDelaySeconds: 120
    periodSeconds: 20
  readinessProbe:
    initialDelaySeconds: 120
    periodSeconds: 10
  
  clickhouse:
    maxMemoryUsage: 2147483648 # 2GB
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
  # Explicitly point to the server service to fix "grpc client not connected"
  deepflowServerNodeIPS:
    - deepflow-server
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

# 5.a. Post-Install Patches (Critical for OCI/ARM64)
echo "🔧 Applying Critical Patches..."
# Fix 1: Server Deadlock (Server needs to reach itself via Service IP to become valid)
ssh oci-k8s-master "kubectl patch svc -n deepflow deepflow-server -p '{\"spec\": {\"publishNotReadyAddresses\": true}}'" >/dev/null 2>&1 || true

# Fix 3: ClickHouse Deadlock (Needs to resolve itself before Ready)
ssh oci-k8s-master "kubectl patch svc -n deepflow deepflow-clickhouse-headless -p '{\"spec\": {\"publishNotReadyAddresses\": true}}'" >/dev/null 2>&1 || true

# Fix 4: DNS Resolution with HostNetwork (Critical for MySQL connection)
ssh oci-k8s-master "kubectl patch deploy -n deepflow deepflow-server -p '{\"spec\": {\"template\": {\"spec\": {\"dnsPolicy\": \"ClusterFirstWithHostNet\"}}}}'" >/dev/null 2>&1 || true

# Fix 1.b: MySQL Deadlock (Similar to Server, MySQL might be slow to come up)
ssh oci-k8s-master "kubectl patch svc -n deepflow deepflow-mysql -p '{\"spec\": {\"publishNotReadyAddresses\": true}}'" >/dev/null 2>&1 || true

# Fix 1.c: MySQL DNS Resolution Fix (Optimization)
ssh oci-k8s-master "kubectl patch deploy -n deepflow deepflow-mysql --type='json' -p='[{\"op\": \"add\", \"path\": \"/spec/template/spec/containers/0/args\", \"value\": [\"--skip-name-resolve\"]}]'" >/dev/null 2>&1 || true

# Fix 1.d: Pin Server to k8s-node-1 (Stability) and define NODE_IP
echo "🔧 Applying Critical Patches..."
NODE_IP=$(ssh oci-k8s-master "kubectl get nodes k8s-node-1 -o jsonpath='{.status.addresses[?(@.type==\"InternalIP\")].address}'" 2>/dev/null || echo "10.0.1.221")
if [ -z "$NODE_IP" ]; then NODE_IP="10.0.1.221"; fi

ssh oci-k8s-master "kubectl patch deploy -n deepflow deepflow-server -p '{\"spec\": {\"template\": {\"spec\": {\"nodeSelector\": {\"kubernetes.io/hostname\": \"k8s-node-1\"}}}}}'" >/dev/null 2>&1 || true

# Fix 1.e: Patch Server and App Config to use IPs (Bypass DNS in HostNetwork)
MYSQL_IP=$(ssh oci-k8s-master "kubectl get svc -n deepflow deepflow-mysql -o jsonpath='{.spec.clusterIP}'")
SERVER_CONFIG=$(ssh oci-k8s-master "kubectl get cm -n deepflow deepflow -o jsonpath='{.data.server\.yaml}'" | sed "s/host: deepflow-mysql/host: $MYSQL_IP/g" | sed "s/controller:/controller:\\n  trisolaris:\\n    node-ip: ${NODE_IP}/")
APP_CONFIG=$(ssh oci-k8s-master "kubectl get cm -n deepflow deepflow -o jsonpath='{.data.app\.yaml}'" | sed "s/host: deepflow-server/host: ${NODE_IP}/g")

ssh oci-k8s-master "kubectl patch cm -n deepflow deepflow -p '{\"data\": {\"server.yaml\": \"$(echo "$SERVER_CONFIG" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')\", \"app.yaml\": \"$(echo "$APP_CONFIG" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')\"}}'" >/dev/null 2>&1 || true

# Fix 3: Bootstrap Control Plane DB (Fixes "No Data" / Loopback Issue)
# Manually insert Controller and Analyzer records if missing, as HostNetwork self-discovery is flaky
ssh oci-k8s-master "kubectl exec -n deepflow deepflow-mysql-0 -- mysql -u root -pdeepflow -e \"
INSERT IGNORE INTO deepflow.controller (state, name, ip, lcuuid, synced_at, node_type, region_domain_prefix, node_name, pod_name, pod_ip, vtap_max) VALUES (2, 'k8s-node-1', '${NODE_IP}', UUID(), NOW(), 1, '', 'k8s-node-1', 'deepflow-server', '${NODE_IP}', 2000);
INSERT IGNORE INTO deepflow.analyzer (state, name, ip, lcuuid, synced_at, pod_name, pod_ip, vtap_max) VALUES (1, 'k8s-node-1', '${NODE_IP}', UUID(), NOW(), 'deepflow-server', '${NODE_IP}', 2000);
INSERT IGNORE INTO deepflow.az_controller_connection (az, region, controller_ip, lcuuid) VALUES ('ALL', 'ffffffff-ffff-ffff-ffff-ffffffffffff', '${NODE_IP}', UUID());
INSERT IGNORE INTO deepflow.az_analyzer_connection (az, region, analyzer_ip, lcuuid) VALUES ('ALL', 'ffffffff-ffff-ffff-ffff-ffffffffffff', '${NODE_IP}', UUID());
\"" >/dev/null 2>&1 || true

# Restart to pick up changes
ssh oci-k8s-master "kubectl rollout restart deploy -n deepflow deepflow-server" >/dev/null 2>&1 || true
ssh oci-k8s-master "kubectl rollout restart deploy -n deepflow deepflow-app" >/dev/null 2>&1 || true
ssh oci-k8s-master "kubectl rollout restart ds -n deepflow deepflow-agent" >/dev/null 2>&1 || true



# Fix 2: Grafana Init Permission (Init container cannot write to volume as non-root)
ssh oci-k8s-master "kubectl patch deploy -n deepflow deepflow-grafana -p '{\"spec\": {\"template\": {\"spec\": {\"initContainers\": [{\"name\": \"init-custom-plugins\", \"securityContext\": {\"runAsUser\": 0, \"runAsNonRoot\": false}}, {\"name\": \"init-grafana-ds-dh\", \"securityContext\": {\"runAsUser\": 0, \"runAsNonRoot\": false}}]}}}}'" >/dev/null 2>&1 || true

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
