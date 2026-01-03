#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

install_longhorn() {
  echo "📦 Installing Longhorn for distributed block storage..."
  
  # Install prerequisites on all nodes
  for n in "${NODES[@]}"; do
    run_remote "$n" '
      echo "🔧 Installing Longhorn prerequisites on $(hostname)..."
      
      # Install required packages
      sudo apt-get update -qq
      sudo apt-get install -y -qq open-iscsi nfs-common jq
      
      # Enable and start open-iscsi service
      sudo systemctl enable --now iscsid
      sudo systemctl restart iscsid
      
      echo "🔧 Enabling shared mount propagation (rshared) on / and /var..."
      sudo mount --make-rshared /
      sudo mount --make-rshared /var
      
      # ✅ Make mount propagation persistent across reboots
      echo "🔧 Making mount propagation persistent..."
      if ! grep -q "make-rshared" /etc/rc.local 2>/dev/null; then
        # Create rc.local if it does not exist
        if [ ! -f /etc/rc.local ]; then
          echo "#!/bin/bash" | sudo tee /etc/rc.local >/dev/null
          sudo chmod +x /etc/rc.local
        fi
        # Add mount propagation commands before exit 0
        sudo sed -i "/^exit 0/d" /etc/rc.local 2>/dev/null || true
        echo "mount --make-rshared /
mount --make-rshared /var
exit 0" | sudo tee -a /etc/rc.local >/dev/null
        echo "✅ Added mount propagation to rc.local"
      else
        echo "✅ Mount propagation persistence already configured"
      fi
      
      echo "🔧 Ensuring kubelet MountFlags=shared..."
      sudo mkdir -p /etc/systemd/system/kubelet.service.d
      if ! grep -q "MountFlags=shared" /etc/systemd/system/kubelet.service.d/override.conf 2>/dev/null; then
        echo "[Service]
MountFlags=shared" | sudo tee /etc/systemd/system/kubelet.service.d/override.conf >/dev/null
        echo "✅ Added MountFlags=shared override"
      else
        echo "✅ MountFlags=shared already configured"
      fi
      
      echo "🔄 Reloading kubelet and containerd..."
      sudo systemctl daemon-reexec
      sudo systemctl daemon-reload
      sudo systemctl restart containerd
      sudo systemctl restart kubelet
      echo "✅ Prerequisites installed on $(hostname)"
    '
  done
  
  # Install Longhorn on the cluster
  run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail <<'EOF'
if kubectl -n longhorn-system get deploy longhorn-driver-deployer >/dev/null 2>&1; then
  echo '✅ Longhorn already installed — skipping.'
else
  echo '🚀 Deploying Longhorn v${LONGHORN_VERSION}...'
  kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/longhorn.yaml
  
  echo '⏳ Waiting for Longhorn system to become ready...'
  kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer --timeout=5m || true
  kubectl -n longhorn-system rollout status deploy/longhorn-ui --timeout=5m || true
  
  echo '⏳ Waiting for Longhorn to be fully operational...'
  sleep 10
  
  # Wait for daemonsets to be ready
  kubectl -n longhorn-system rollout status ds/longhorn-manager --timeout=5m || true
  
  echo '✅ Longhorn v${LONGHORN_VERSION} installed successfully.'
  echo '💡 Longhorn UI can be accessed via: kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80'

  # Tuning for Small Clusters (Prevent "Scheduling Failed" on high disk usage)
  echo '🔧 Tuning Longhorn settings for small clusters...'
  kubectl patch -n longhorn-system settings storage-minimal-available-percentage -p '{"value":"15"}' --type=merge
  kubectl patch -n longhorn-system settings storage-over-provisioning-percentage -p '{"value":"200"}' --type=merge
  echo '✅ Tuned: storage-minimal-available-percentage=15%, over-provisioning=200%'

  echo '🔧 Tuning Longhorn Manager resources...'
  kubectl patch -n longhorn-system ds longhorn-manager --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"longhorn-manager","resources":{"requests":{"cpu":"100m","memory":"256Mi"},"limits":{"memory":"1Gi"}}}]}}}}'
  echo '✅ Appied resource limits to longhorn-manager.'

  # Patch Longhorn Manager & Engine Image for Resilience (15s Timeout)
  echo "🩹 Applying Resilience Patches (Manager Resource Limits + Engine Timeout)..."
  kubectl -n longhorn-system patch deployment longhorn-manager --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/cpu", "value": "200m"}, {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"}, {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/cpu", "value": "50m"}, {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "256Mi"}]' || true

  # Patch Engine Image DaemonSet (Increase Probe Timeout for IO-starved nodes)
  # Note: The DS name is dynamic (e.g., engine-image-ei-xxxx), so we find it first.
  kubectl get ds -n longhorn-system -l longhorn.io/component=engine-image -o name | xargs -I {} kubectl patch -n longhorn-system {} --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/timeoutSeconds", "value": 15}, {"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/timeoutSeconds", "value": 15}]' || true

  echo '🔧 Tuning Longhorn UI resources...'
  kubectl patch -n longhorn-system deploy longhorn-ui --type=strategic -p '{"spec":{"template":{"spec":{"containers":[{"name":"longhorn-ui","resources":{"requests":{"cpu":"50m","memory":"64Mi"},"limits":{"memory":"256Mi"}}}]}}}}'
  echo '✅ Appied resource limits to longhorn-ui.'
fi
EOF
"
}

install_longhorn
