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

# Get Serial Console (Boot Logs)
# Usage: get_instance_console_history "ocid1.instance..."
get_instance_console_history() {
    local ocid="$1"
    
    # 1. Create Console History Request
    # echo "Requesting console capture..." >&2
    # Note: Command is 'capture', not 'create' despite being a creation op
    local history_id=$(oci compute console-history capture \
        --instance-id "$ocid" \
        --display-name "ops-rescue-$(date +%s)" \
        --query "data.id" \
        --raw-output 2> /tmp/oci_capture_error.log)
        
    if [[ -z "$history_id" ]]; then
        echo "Error: Failed to create console history request." >&2
        return 1
    fi
    
    # 2. Wait for it to be ready (SUCCEEDED)
    # echo "Waiting for capture to complete..." >&2
    oci compute console-history get \
        --instance-console-history-id "$history_id" \
        --wait-for-state "SUCCEEDED" \
        --wait-interval-seconds 2 \
        --max-wait-seconds 60 >/dev/null 2>&1
        
    # 3. Download and Decode content
    # The content comes raw (usually) or encoded. OCI CLI handles decoding with --file sometimes,
    # but 'get-content' usually outputs to stdout.
    
    local tmp_log="/tmp/console_hist_${ocid}.log"
    
    oci compute console-history get-content \
        --instance-console-history-id "$history_id" \
        --file "$tmp_log" \
        --length 100000 \
        2>> /tmp/oci_capture_error.log
        
    if [[ -f "$tmp_log" ]]; then
        cat "$tmp_log"
        rm -f "$tmp_log"
    fi

    # 4. Clean up (Optional, but good hygiene)
    oci compute console-history delete \
        --instance-console-history-id "$history_id" \
        --force >/dev/null 2>&1 &
}

# --- Volume Management Functions ---

# Stop Instance
# Usage: stop_instance "ocid..."
stop_instance() {
    local ocid="$1"
    oci compute instance action \
        --instance-id "$ocid" \
        --action "STOP" \
        --wait-for-state "STOPPED" \
        --wait-interval-seconds 10 \
        --max-wait-seconds 600 > /dev/null
}

# Start Instance
# Usage: start_instance "ocid..."
start_instance() {
    local ocid="$1"
    oci compute instance action \
        --instance-id "$ocid" \
        --action "START" \
        --wait-for-state "RUNNING" \
        --wait-interval-seconds 10 \
        --max-wait-seconds 600 > /dev/null
}

# Get Boot Volume Attachment ID
# Usage: get_boot_volume_attachment_id "instance_ocid"
get_boot_volume_attachment_id() {
    local instance_id="$1"
    local compartment_id=$(get_tenancy_id)
    
    oci compute boot-volume-attachment list \
        --compartment-id "$compartment_id" \
        --instance-id "$instance_id" \
        --query "data[0].id" \
        --raw-output 2>/dev/null
}

# Get Boot Volume ID from Attachment
# Usage: get_boot_volume_id_from_attachment "attachment_id"
get_boot_volume_id_from_attachment() {
    local attachment_id="$1"
    oci compute boot-volume-attachment get \
        --boot-volume-attachment-id "$attachment_id" \
        --query "data.\"boot-volume-id\"" \
        --raw-output 2>/dev/null
}

# Detach Boot Volume
# Usage: detach_boot_volume "attachment_id"
detach_boot_volume() {
    local attachment_id="$1"
    oci compute boot-volume-attachment detach \
        --boot-volume-attachment-id "$attachment_id" \
        --wait-for-state "DETACHED" \
        --wait-interval-seconds 5 \
        --max-wait-seconds 300 > /dev/null
}

# Attach Boot Volume (Restoring as Boot Volume)
# Usage: attach_boot_volume "instance_ocid" "volume_ocid"
attach_boot_volume() {
    local instance_id="$1"
    local volume_id="$2"
    
    oci compute boot-volume-attachment attach \
        --instance-id "$instance_id" \
        --boot-volume-id "$volume_id" \
        --wait-for-state "ATTACHED" \
        --wait-interval-seconds 5 \
        --max-wait-seconds 300 > /dev/null
}

# Attach Volume as Data Disk (for Rescue)
# Usage: attach_volume_as_data "instance_ocid" "volume_ocid"
attach_volume_as_data() {
    local instance_id="$1"
    local volume_id="$2"
    
    oci compute volume-attachment attach \
        --instance-id "$instance_id" \
        --volume-id "$volume_id" \
        --type "iscsi" \
        --display-name "RESCUE_VOL" \
        --wait-for-state "ATTACHED" \
        --wait-interval-seconds 5 \
        --max-wait-seconds 300 > /dev/null
}

# Get Volume Attachment ID (Data Volume)
# Usage: get_data_volume_attachment_id "instance_ocid" "volume_ocid"
get_data_volume_attachment_id() {
    local instance_id="$1"
    local volume_id="$2"
    local compartment_id=$(get_tenancy_id)
    
    oci compute volume-attachment list \
        --compartment-id "$compartment_id" \
        --instance-id "$instance_id" \
        --volume-id "$volume_id" \
        --query "data[0].id" \
        --raw-output 2>/dev/null
}

# Detach Data Volume
# Usage: detach_data_volume "attachment_id"
detach_data_volume() {
    local attachment_id="$1"
    oci compute volume-attachment detach \
        --volume-attachment-id "$attachment_id" \
        --wait-for-state "DETACHED" \
        --wait-interval-seconds 5 \
        --max-wait-seconds 300 > /dev/null
}


# --- Volume Management Functions ---

# Stop Instance
# Usage: stop_instance "ocid..."
stop_instance() {
    local ocid="$1"
    oci compute instance action \
        --instance-id "$ocid" \
        --action "STOP" \
        --wait-for-state "STOPPED" \
        --wait-interval-seconds 10 \
        --max-wait-seconds 600 > /dev/null
}

# Start Instance
# Usage: start_instance "ocid..."
start_instance() {
    local ocid="$1"
    oci compute instance action \
        --instance-id "$ocid" \
        --action "START" \
        --wait-for-state "RUNNING" \
        --wait-interval-seconds 10 \
        --max-wait-seconds 600 > /dev/null
}

# Get Boot Volume Attachment ID
# Usage: get_boot_volume_attachment_id "instance_ocid"
get_boot_volume_attachment_id() {
    local instance_id="$1"
    local compartment_id=$(get_tenancy_id)
    
    oci compute boot-volume-attachment list \
        --compartment-id "$compartment_id" \
        --instance-id "$instance_id" \
        --query "data[0].id" \
        --raw-output 2>/dev/null
}

# Get Boot Volume ID from Attachment
# Usage: get_boot_volume_id_from_attachment "attachment_id"
get_boot_volume_id_from_attachment() {
    local attachment_id="$1"
    oci compute boot-volume-attachment get \
        --boot-volume-attachment-id "$attachment_id" \
        --query "data.\"boot-volume-id\"" \
        --raw-output 2>/dev/null
}

# Detach Boot Volume
# Usage: detach_boot_volume "attachment_id"
detach_boot_volume() {
    local attachment_id="$1"
    oci compute boot-volume-attachment detach \
        --boot-volume-attachment-id "$attachment_id" \
        --wait-for-state "DETACHED" \
        --wait-interval-seconds 5 \
        --max-wait-seconds 300 > /dev/null
}

# Attach Boot Volume (Restoring as Boot Volume)
# Usage: attach_boot_volume "instance_ocid" "volume_ocid"
attach_boot_volume() {
    local instance_id="$1"
    local volume_id="$2"
    
    oci compute boot-volume-attachment attach \
        --instance-id "$instance_id" \
        --boot-volume-id "$volume_id" \
        --wait-for-state "ATTACHED" \
        --wait-interval-seconds 5 \
        --max-wait-seconds 300 > /dev/null
}

# Attach Volume as Data Disk (for Rescue)
# Usage: attach_volume_as_data "instance_ocid" "volume_ocid"
attach_volume_as_data() {
    local instance_id="$1"
    local volume_id="$2"
    
    oci compute volume-attachment attach \
        --instance-id "$instance_id" \
        --volume-id "$volume_id" \
        --type "iscsi" \
        --display-name "RESCUE_VOL" \
        --wait-for-state "ATTACHED" \
        --wait-interval-seconds 5 \
        --max-wait-seconds 300 > /dev/null
}

# Get Volume Attachment ID (Data Volume)
# Usage: get_data_volume_attachment_id "instance_ocid" "volume_ocid"
get_data_volume_attachment_id() {
    local instance_id="$1"
    local volume_id="$2"
    local compartment_id=$(get_tenancy_id)
    
    oci compute volume-attachment list \
        --compartment-id "$compartment_id" \
        --instance-id "$instance_id" \
        --volume-id "$volume_id" \
        --query "data[0].id" \
        --raw-output 2>/dev/null
}

# Detach Data Volume
# Usage: detach_data_volume "attachment_id"
detach_data_volume() {
    local attachment_id="$1"
    oci compute volume-attachment detach \
        --volume-attachment-id "$attachment_id" \
        --wait-for-state "DETACHED" \
        --wait-interval-seconds 5 \
        --max-wait-seconds 300 > /dev/null
}

# Check if SSH is allowed from Current IP
# Usage: check_ssh_allowed_from_ip "instance_ocid"
# Returns 0 if allowed, 1 if blocked/unknown
check_ssh_allowed_from_ip() {
    local instance_id="$1"
    
    # 1. Get Current Public IP
    local my_ip=$(curl -s --connect-timeout 2 ifconfig.me)
    if [[ -z "$my_ip" ]]; then
        echo "Warning: Could not determine public IP." >&2
        return 1
    fi
    
    # 2. Get VNIC -> Subnet
    # Get Primary VNIC ID
    local vnic_id=$(oci compute instance list-vnics \
        --instance-id "$instance_id" \
        --query "data[0].id" \
        --raw-output 2>/dev/null)
        
    if [[ -z "$vnic_id" ]]; then return 1; fi
    
    local subnet_id=$(oci network vnic get \
        --vnic-id "$vnic_id" \
        --query "data.\"subnet-id\"" \
        --raw-output 2>/dev/null)
        
    if [[ -z "$subnet_id" ]]; then return 1; fi
    
    # 3. Get Security List Rules
    # Complex query: Get all sec lists for subnet -> merge ingress rules
    # Simplified: Check if ANY rule allows my_ip (or 0.0.0.0/0) on port 22
    
    local allowed=$(oci network security-list list \
        --compartment-id "$(get_tenancy_id)" \
        --vnic-id "$vnic_id" \
        --query "data[?contains(\"subnet-id\", '$subnet_id')].\"ingress-security-rules\"[] | [?protocol=='6' && tcp-options.destination-port-range.min<='22' && tcp-options.destination-port-range.max>='22']" \
        --raw-output 2>/dev/null)
        
    # This query is tricky. Let's just dump the rules and grep for standard "0.0.0.0/0" or my_ip
    # We need to look for Subnet's Sec Lists.
    
    # Actually, `oci network security-list list --subnet-id` is not valid directly, it needs compartment.
    # But filtering by VCN/Compartment is better.
    # Let's use a simpler heuristic for TUI speed:
    # Just list all sec lists in compartment, check if any have ingress 0.0.0.0/0 tcp 22.
    # Correctness vs Speed trade-off. Correctness is better.
    
    # Real logic: Subnet -> Security List IDs.
    local sl_ids=$(oci network subnet get --subnet-id "$subnet_id" --query "data.\"security-list-ids\"" --raw-output 2>/dev/null)
    
    # Iterate and check
    local found_match=false
    # Remove brackets/quotes
    sl_ids=$(echo "$sl_ids" | tr -d '[]", ')
    
    for slid in $sl_ids; do
        # Get Rules
        local rules=$(oci network security-list get --security-list-id "$slid" --query "data.\"ingress-security-rules\"" 2>/dev/null)
        
        # Check for 0.0.0.0/0 on 22
        if echo "$rules" | grep -q "0.0.0.0/0"; then
             if echo "$rules" | grep -q '"min": 22'; then
                 found_match=true
                 break
             fi
        fi
        
        # Check for MY IP
        if echo "$rules" | grep -q "$my_ip"; then
             if echo "$rules" | grep -q '"min": 22'; then
                 found_match=true
                 break
             fi
        fi
    done
    
    if [[ "$found_match" == "true" ]]; then
        return 0
    else
        echo "$my_ip" # Return the blocked IP for info
        return 1
    fi
}

# Add Ingress Rule for Current IP (Port 22)
# Usage: whitelist_my_ip "instance_ocid"
whitelist_my_ip() {
    local instance_id="$1"
    
    # 1. Get IP — prefer IPv4; ifconfig.me may return IPv6 on dual-stack hosts
    local my_ip=$(curl -s --connect-timeout 2 -4 ifconfig.me 2>/dev/null)
    if [[ -z "$my_ip" ]]; then
        my_ip=$(curl -s --connect-timeout 2 ifconfig.me)
    fi
    if [[ -z "$my_ip" ]]; then echo "Error: No IP"; return 1; fi
    # Add CIDR suffix — /128 for IPv6, /32 for IPv4
    local cidr_prefix=32
    if [[ "$my_ip" == *:* ]]; then cidr_prefix=128; fi
    local cidr="${my_ip}/${cidr_prefix}"
    
    echo "Whitelisting $cidr..."
    
    # 2. Get Security List ID (First one active on VNIC)
    local vnic_id=$(oci compute instance list-vnics --instance-id "$instance_id" --query "data[0].id" --raw-output 2>/dev/null)
    local subnet_id=$(oci network vnic get --vnic-id "$vnic_id" --query "data.\"subnet-id\"" --raw-output 2>/dev/null)
    local sl_id=$(oci network subnet get --subnet-id "$subnet_id" --query "data.\"security-list-ids\"[0]" --raw-output 2>/dev/null)
    
    if [[ -z "$sl_id" || "$sl_id" == "null" ]]; then
        echo "Error: Could not determine Security List."
        return 1
    fi
    
    # 3. Get Current Rules (JSON)
    local current_rules_json=$(oci network security-list get --security-list-id "$sl_id" --query "data.\"ingress-security-rules\"" 2>/dev/null)
    
    # 4. Construct New Rule (JSON)
    # Note: "6" is TCP. "source" is the CIDR.
    local new_rule_json=$(cat <<EOF
    {
        "description": "Auto-Whitelisted by Rescue Tool $(date +%F)",
        "is-stateless": false,
        "protocol": "6",
        "source": "$cidr",
        "source-type": "CIDR_BLOCK",
        "tcp-options": {
            "destination-port-range": {
                "max": 22,
                "min": 22
            },
            "source-port-range": null
        },
        "udp-options": null,
        "icmp-options": null
    }
EOF
)

    # 5. Merge and Update
    # Using jq to append.
    # We rely on jq being installed. OCI Cloud Shell usually has it. Ubuntu usually has it.
    if ! command -v jq &> /dev/null; then
        echo "Error: 'jq' tool is required to edit security lists."
        return 1
    fi
    
    # Append the new rule object to the array
    # Careful with jq syntax.
    local updated_rules_json=$(echo "$current_rules_json" | jq --argjson new "$new_rule_json" '. + [$new]')
    
    if [[ -z "$updated_rules_json" ]]; then
        echo "Error: Failed to process JSON rules."
        return 1
    fi
    
    # 6. Apply Update
    # We must write to a temp file because argument might be too long
    local tmp_json="/tmp/sec_list_update_$$.json"
    echo "$updated_rules_json" > "$tmp_json"
    
    oci network security-list update \
        --security-list-id "$sl_id" \
        --ingress-security-rules "file://$tmp_json" \
        --force >/dev/null
        
    rm -f "$tmp_json"
    
    
    echo "Success. Added $cidr to Security List."
    return 0
}

