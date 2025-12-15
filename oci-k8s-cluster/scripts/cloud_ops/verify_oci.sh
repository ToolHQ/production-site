#!/bin/bash
# scripts/cloud_ops/verify_oci.sh
# Test Driver for Cloud Ops

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/../../common.sh"
source "$SCRIPT_DIR/../../lib/oci_wrapper.sh"
source "$SCRIPT_DIR/tui_cloud.sh"

echo "=== Testing Authentication ==="
if check_oci_auth; then
    echo "Auth: OK"
else
    echo "Auth: FAIL"
    exit 1
fi

echo -e "\n=== Testing Diagnosis on HEALTHY Node (Master) ==="
# Get IP of master
master_ip=$(run_kubectl "get node k8s-master -o jsonpath='{.status.addresses[?(@.type==\"InternalIP\")].address}'")
perform_diagnosis "k8s-master" "$master_ip"

echo -e "\n=== Test Complete ==="
