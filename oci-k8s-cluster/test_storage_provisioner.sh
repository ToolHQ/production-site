#!/usr/bin/env bash
# ---------------------------------------------------------------
# Test script for storage provisioner management functions
# ---------------------------------------------------------------
set -euo pipefail

# Source the common functions
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/common.sh"

# Source the storage provisioner functions from setup script
# We extract just the functions we need to test
source <(sed -n '/^# === Storage Provisioner Detection/,/^install_storage_provisioner() {/p' "$SCRIPT_DIR/setup_k8s_cluster.sh" | head -n -1)

# Mock MASTER_NODE if not set for local testing
if [[ -z "${MASTER_NODE:-}" ]]; then
  echo "⚠️  MASTER_NODE not set - this test requires a real cluster"
  echo "   Set MASTER_NODE to your cluster master node SSH alias"
  exit 1
fi

echo "🧪 Storage Provisioner Management Tests"
echo "========================================"
echo ""

# Test 1: Detect installed provisioners
echo "Test 1: Detecting installed provisioners..."
installed=$(detect_installed_provisioner)
if [[ -n "$installed" ]]; then
  echo "✅ Detected: $installed"
else
  echo "⚠️  No provisioners detected"
fi
echo ""

# Test 2: Get version if something is installed
if [[ -n "$installed" ]]; then
  IFS=',' read -ra provisioners <<< "$installed"
  for prov in "${provisioners[@]}"; do
    echo "Test 2: Getting version of $prov..."
    version=$(get_provisioner_version "$prov")
    if [[ -n "$version" ]]; then
      echo "✅ Version: v$version"
    else
      echo "⚠️  Could not determine version"
    fi
    echo ""
  done
fi

# Test 3: List PVCs (read-only test)
echo "Test 3: Listing PVCs by storage class..."
for sc in "longhorn" "local-path" "manual"; do
  echo "  Storage class: $sc"
  run_remote_capture "$MASTER_NODE" "kubectl get pvc --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.storageClassName==\"$sc\") | \"    \\(.metadata.namespace)/\\(.metadata.name)\"' || echo '    (none)'"
  echo "$RUN_REMOTE_CAPTURE_RESULT" | sed 's/^\[.*\] //'
done
echo ""

# Test 4: Verify health of installed provisioners
if [[ -n "$installed" ]]; then
  IFS=',' read -ra provisioners <<< "$installed"
  for prov in "${provisioners[@]}"; do
    echo "Test 4: Verifying health of $prov..."
    if verify_provisioner_health "$prov"; then
      echo "✅ Health check passed"
    else
      echo "❌ Health check failed"
    fi
    echo ""
  done
fi

echo "========================================"
echo "🎉 All tests completed!"
echo ""
echo "💡 To test the full migration workflow:"
echo "   1. Set STORAGE_PROVISIONER to your desired provisioner"
echo "   2. Run: ./setup_k8s_cluster.sh"
echo "   3. The script will automatically handle detection, migration, and cleanup"
