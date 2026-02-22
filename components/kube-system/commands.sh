#!/usr/bin/env bash
# Managed by Antigravity (T-096)
# Robust Control Plane Resource Tuning
set -euo pipefail

echo "⚖️ Tuning Kube-System Static Pod Resources..."

patch_manifest() {
  local file=$1
  local comp_name=$2
  local cpu_req=$3
  local mem_req=$4
  local cpu_lim=$5
  local mem_lim=$6

  if [ -f "$file" ]; then
    echo "  - Patching $comp_name ($file)..."
    # We use perl for safe multi-line replacement of the resources block.
    # This pattern identifies the 'resources:' block (and surrounding probe/ports)
    # and replaces it with a clean, indented version.
    sudo perl -0777 -pi -e "s/(containers:\n\s+-\s+)(?:name: \Q$comp_name\E\n\s+)?(command:)/\${1}name: $comp_name\n    \${2}/g" "$file"
    
    # Now replace the resources block specifically
    # Pattern: match from 'resources:' to the next key at the same indentation level (usually 'startupProbe' or 'volumeMounts')
    # We use a conservative replacement that preserves the rest of the manifest.
    sudo perl -0777 -pi -e "s/resources:.*?\n\s+([a-zA-Z]+:)/resources:\n      requests:\n        cpu: $cpu_req\n        memory: $mem_req\n      limits:\n        cpu: $cpu_lim\n        memory: $mem_lim\n    \$1/s" "$file"
  else
    echo "  - Skipping $comp_name (manifest not found)."
  fi
}

# Apply Tuning
patch_manifest "/etc/kubernetes/manifests/kube-apiserver.yaml" "kube-apiserver" "250m" "512Mi" "500m" "1Gi"
patch_manifest "/etc/kubernetes/manifests/kube-controller-manager.yaml" "kube-controller-manager" "100m" "64Mi" "300m" "128Mi"
patch_manifest "/etc/kubernetes/manifests/kube-scheduler.yaml" "kube-scheduler" "50m" "32Mi" "150m" "64Mi"
patch_manifest "/etc/kubernetes/manifests/etcd.yaml" "etcd" "100m" "512Mi" "200m" "1Gi"

echo "✅ Control plane tuning complete."

# --- T-100: Zero-Waste Lockdown ---
echo "🔒 Applying Resource LimitRange for kube-system..."

if [ -f "limit-range.yaml" ]; then
    kubectl apply -f limit-range.yaml
    echo "  - Applied limit-range.yaml"
fi


