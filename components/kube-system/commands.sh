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

# --- T-192: Apiserver livenessProbe + throttling ---
echo "🛡️ T-192: Applying kube-apiserver livenessProbe + request throttling..."
python3 - <<'PYEOF'
import yaml, sys

MANIFEST = "/etc/kubernetes/manifests/kube-apiserver.yaml"
with open(MANIFEST) as f:
    m = yaml.safe_load(f)
c = m["spec"]["containers"][0]

for flag in ["--max-requests-inflight=150", "--max-mutating-requests-inflight=50"]:
    key = flag.split("=")[0]
    if not any(x.startswith(key) for x in c["command"]):
        c["command"].append(flag)
        print("  Added: " + flag)

if "livenessProbe" not in c:
    c["livenessProbe"] = {
        "failureThreshold": 3,
        "httpGet": {"host": "10.0.1.100", "path": "/livez", "port": 6443, "scheme": "HTTPS"},
        "initialDelaySeconds": 10,
        "periodSeconds": 30,
        "timeoutSeconds": 10
    }
    print("  Added: livenessProbe")

with open(MANIFEST, "w") as f:
    yaml.dump(m, f, default_flow_style=False, allow_unicode=True)
print("  kube-apiserver patched OK")
PYEOF

# --- T-192: Etcd compaction + quota ---
echo "🛡️ T-192: Applying etcd auto-compaction + quota-backend..."
python3 - <<'PYEOF'
import yaml

MANIFEST = "/etc/kubernetes/manifests/etcd.yaml"
with open(MANIFEST) as f:
    m = yaml.safe_load(f)
c = m["spec"]["containers"][0]

for flag in ["--auto-compaction-retention=8h", "--quota-backend-bytes=1610612736"]:
    key = flag.split("=")[0]
    if not any(x.startswith(key) for x in c["command"]):
        c["command"].append(flag)
        print("  Added: " + flag)

with open(MANIFEST, "w") as f:
    yaml.dump(m, f, default_flow_style=False, allow_unicode=True)
print("  etcd patched OK")
PYEOF

# --- T-100: Zero-Waste Lockdown ---
echo "🔒 Applying Resource LimitRange for kube-system..."

if [ -f "limit-range.yaml" ]; then
    kubectl apply -f limit-range.yaml
    echo "  - Applied limit-range.yaml"
fi

if [ -f "snapshot-controller-patch.yaml" ] && kubectl get deployment -n kube-system snapshot-controller >/dev/null 2>&1; then
  kubectl patch deployment -n kube-system snapshot-controller --patch-file snapshot-controller-patch.yaml
  echo "  - Patched snapshot-controller"
fi

echo "🛡️ Deploying ResourceQuotas for all namespaces..."
if [ -f "resource-quotas.yaml" ]; then
    kubectl apply -f resource-quotas.yaml
    echo "  - Applied resource-quotas.yaml"
fi


