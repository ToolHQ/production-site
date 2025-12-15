#!/bin/bash
# lib/oci_wrapper.sh
# Wrapper for Oracle Cloud Infrastructure (OCI) CLI interactions.
# Focus: Compute Instance Management (Status, Metrics, Reboot).

# Check if OCI CLI is available and authenticated
check_oci_auth() {
    if ! command -v oci &> /dev/null; then
        return 1
    fi
    # Quick check by listing regions (fastest call)
    if ! oci iam region list &> /dev/null; then
        return 2
    fi
    return 0
}

# Get Compartment ID (Implicitly using Root Tenancy from config if not specified)
# Returns the OCID of the tenancy from ~/.oci/config
get_tenancy_id() {
    grep "tenancy=" ~/.oci/config | cut -d"=" -f2 | tr -d ' '
}

# Lookup Instance OCID by Display Name
# Usage: get_instance_ocid_by_name "k8s-node-3"
get_instance_ocid_by_name() {
    local node_name="$1"
    local tenancy_id=$(get_tenancy_id)
    
    # Assuming instances are in the root compartment (Tenancy) for simplicity this env
    # Using --raw-output to get clean ID
    oci compute instance list \
        --compartment-id "$tenancy_id" \
        --display-name "$node_name" \
        --query "data[0].id" \
        --raw-output 2>/dev/null
}

# Get Instance Lifecycle State
# Usage: get_instance_status "ocid1.instance..."
# Returns: RUNNING, STOPPED, TERMINATED, etc.
get_instance_status() {
    local ocid="$1"
    oci compute instance get \
        --instance-id "$ocid" \
        --query "data.\"lifecycle-state\"" \
        --raw-output 2>/dev/null
}

# Get Recent CPU Metrics (Last 5 mins) to detect "Zombie" state
# Usage: get_instance_cpu_metrics "ocid1.instance..."
# Returns: "No Data" or average CPU val. 
get_instance_cpu_metrics() {
    local ocid="$1"
    local tenancy_id=$(get_tenancy_id)
    local start_time=$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
    local end_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Query "CpuUtilization" for ALL instances, then filter client-side using JMESPath
    # This avoids "No such option: --dimension-filters" on older CLIs and MQL quoting hell
    local result=$(oci monitoring metric-data summarize-metrics-data \
        --namespace "oci_computeagent" \
        --query-text "CpuUtilization[1m].mean()" \
        --compartment-id "$tenancy_id" \
        --start-time "$start_time" \
        --end-time "$end_time" \
        --query "data[?dimensions.resourceId=='$ocid'].\"aggregated-datapoints\"[0].value | [0]" \
        --raw-output 2>/dev/null)
        
    if [[ "$result" == "null" || -z "$result" ]]; then
        echo "No Data"
    else
        echo "$result"
    fi
}

# Force Reboot Instance (HARD RESET)
# Usage: reboot_instance "ocid1.instance..." "RESET"
reboot_instance() {
    local ocid="$1"
    local action="${2:-RESET}" # Default to RESET (Hard Reboot)
    
    oci compute instance action \
        --instance-id "$ocid" \
        --action "$action" \
        --wait-for-state "RUNNING" \
        --wait-interval-seconds 10 \
        --max-wait-seconds 600 > /dev/null
}
