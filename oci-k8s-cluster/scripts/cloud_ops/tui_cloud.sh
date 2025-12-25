#!/bin/bash
# scripts/cloud_ops/tui_cloud.sh
# TUI Interface for OCI Rescue Operations

CLOUD_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source "$CLOUD_DIR/../../common.sh"
source "$CLOUD_DIR/../../lib/oci_wrapper.sh"

# Ensure OCI Wrapper is loaded
if ! check_oci_auth; then
    echo -e "${RED}Error: OCI CLI not configured or authenticated.${NC}"
    echo -e "Please configure ~/.oci/config first."
    read -p "Press Enter to continue..."
    return 1
fi

perform_diagnosis() {
    local node_name="$1"
    local node_ip="${2:-Unknown}"
    
    echo -e "\n${CYAN}Running Smart Diagnosis for ${node_name}...${NC}"
    
    # 1. K8s Status
    # Fix: Use word boundary or exclusion to avoid matching "NotReady" as "Ready"
    if run_kubectl "get node $node_name --no-headers" 2>/dev/null | grep -q "\bReady\b"; then
        local k8s_status="True"
        echo -e "${GREEN}READY${NC}"
    else
        local k8s_status="False"
        echo -e "${RED}NOT READY${NC}"
    fi

    # 2. SSH Reachability
    # Use mapping: k8s-node-x -> oci-k8s-node-x
    local ssh_host="oci-$node_name"
    echo -n "Checking SSH Connectivity ($ssh_host)... "
    if timeout 5 ssh -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$ssh_host" exit 2>/dev/null; then
        echo -e "${GREEN}ONLINE${NC}"
        local ssh_ok=true
    else
        echo -e "${RED}OFFLINE${NC}"
        local ssh_ok=false
        
        # New Feature: Check Security List (Firewall)
        echo -n "Checking Firewall Rules (Port 22)... "
        local ocid_check=$(get_instance_ocid_by_name "$node_name")
        local firewall_status
        if firewall_status=$(check_ssh_allowed_from_ip "$ocid_check"); then
             echo -e "${GREEN}ALLOWED${NC}"
        else
             local my_ip_val="$firewall_status"
             echo -e "${RED}BLOCKED${NC}"
             echo -e "${YELLOW}⚠️  WARNING: SSH appears blocked for your IP (${my_ip_val}).${NC}"
             echo -e "   Check OCI Security List for Subnet."
        fi
    fi

    # 3. OCI Metrics (Cloud Truth)
    # Get OCID first
    echo -n "Fetching OCI Instance ID... "
    local ocid=$(get_instance_ocid_by_name "$node_name")
    if [[ -z "$ocid" ]]; then
        echo -e "${RED}NOT FOUND${NC}"
        return
    else
        echo -e "${GREEN}FOUND${NC} ($ocid)"
    fi
    
    echo -n "Checking Cloud Metrics (CPU Heartbeat)... "
    local cpu_metric=$(get_instance_cpu_metrics "$ocid")
    local cloud_zombie=false
    
    if [[ "$cpu_metric" == "No Data" ]]; then
        echo -e "${RED}NO DATA (Pulse Lost)${NC}"
        cloud_zombie=true
    else
        echo -e "${GREEN}ACTIVE ($cpu_metric%)${NC}"
    fi

    # Conclusion
    echo -e "\n${BOLD}DIAGNOSIS REPORT:${NC}"
    
    # Priority 1: Zombie Detection (OS Dead + Cloud Blind)
    # This overrides K8s status because K8s status can be stale (reporting Ready when actually dead)
    if [[ "$ssh_ok" == "false" && "$cloud_zombie" == "true" ]]; then
        echo -e "${RED}${BOLD}💀 CRITICAL: ZOMBIE NODE DETECTED (OS FROZEN)${NC}"
        echo -e "${YELLOW}Evidence: Node is unresponsive to SSH and stopped sending Cloud Metrics.${NC}"
        if [[ "$k8s_status" == "True" ]]; then
            echo -e "${MAGENTA}Note: K8s still reports 'Ready' (Likely Stale/False Positive).${NC}"
        fi
        echo -e "${RED}Recommendation: HARD REBOOT (RESET) REQUIRED.${NC}"
        return 99 # Zombie Code

    # Priority 1.5: Frozen Detection (OS Unresponsive + Cloud Active)
    elif [[ "$ssh_ok" == "false" ]]; then
         echo -e "${RED}${BOLD}❄️  CRITICAL: NODE FROZEN (High CPU / SSH Unresponsive)${NC}"
         echo -e "${YELLOW}Evidence: Cloud shows Active CPU usage, but SSH is offline.${NC}"
         echo -e "${RED}Recommendation: HARD REBOOT (RESET) REQUIRED.${NC}"
         return 98 # Frozen Code

    # Priority 2: K8s Failure but OS Alive (Appears to be the case now)
    elif [[ "$k8s_status" != "True" && "$ssh_ok" == "true" ]]; then
        echo -e "${YELLOW}WARNING: Node is reachable via SSH but NotReady in K8s.${NC}"
        echo -e "Recommendation: Heavy Load or Kubelet issue. Check 'Live Forensics'."
        return 1
        
    # Priority 3: Healthy
    else
        echo -e "${GREEN}Node appears HEALTHY or issue is partial.${NC}"
        return 0
    fi
}

post_reboot_forensics() {
    local node_name="$1"
    local node_ip="$2"
    local ssh_host="oci-$node_name"
    
    echo -e "\n${MAGENTA}Starting Digital Forensics analysis...${NC}"
    echo -e "Waiting for Node to answer SSH (this may take 2-3 minutes)..."
    
    # Loop wait for SSH
    local retries=30
    while [ $retries -gt 0 ]; do
        if timeout 5 ssh -q -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$ssh_host" exit 2>/dev/null; then
            echo -e "${GREEN}Node Connected!${NC}"
            break
        fi
        echo -n "."
        sleep 5
        ((retries--))
    done
    
    if [ $retries -eq 0 ]; then
        echo -e "${RED}Timeout waiting for node.${NC}"
        return
    fi
    
    echo -e "\n${CYAN}Scanning System Journal (Previous Boot) for causes...${NC}"
    
    # Consolidated Scan with Timeout (20s)
    # Optimized: Limit input to last 10000 lines to prevent timeout on massive logs
    # Added: iscsi, longhorn, mount, multipath (Storage/IO Focus)
    local cmd="journalctl -b -1 -n 10000 --no-pager | grep -E -i 'Out of memory|Kernel panic|I/O error|segfault|Call Trace|hardware error|Ext4-fs error|lockup|iscsi|longhorn|multipath|attach|buildkit|rootlesskit' | tail -n 15"
    
    local output
    # Capture stderr too to catch SSH/Permission errors
    if output=$(timeout 20 ssh -o StrictHostKeyChecking=accept-new "$ssh_host" "$cmd" 2>&1); then
        # Exit 0 = Grep found something
        echo -e "${RED}[!] CRITICAL EVENTS FOUND IN PREVIOUS BOOT:${NC}"
        echo -e "${YELLOW}$output${NC}"
    else
        local ret=$?
        if [ $ret -eq 124 ]; then
             echo -e "${RED}[Error] Log scan timed out (Logs too large or disk slow).${NC}"
        elif [ $ret -eq 255 ]; then
             echo -e "${RED}[Error] SSH Failed to execute command: $output${NC}"
        else
             # Exit 1 = Grep found nothing
             echo -e "${GREEN}No obvious system crashes (OOM/Panic/IO) found in last 10k lines of previous boot.${NC}"
             echo -e "${CYAN}(This suggests the freeze might have been silent/hardware or at the hypervisor level)${NC}"
             
             # Check if we got a permission hint in the "failed" output (grep failed but stderr might have info)
             if echo "$output" | grep -q "Permission denied"; then
                 echo -e "${YELLOW}Warning: Permission denied accessing logs. Try running as root/opc.${NC}"
             fi
        fi
    fi
        
    echo -e "\nWould you like to view the last 50 lines of the log anyway? (y/N)"
    read -r view_raw
    if [[ "$view_raw" =~ ^[Yy]$ ]]; then
        echo -e "---------------------------------------------------"
        ssh -o StrictHostKeyChecking=no "$ssh_host" "journalctl -b -1 -n 50 --no-pager"
        echo -e "---------------------------------------------------"
    fi
    
    echo -e "${GREEN}Forensics Complete.${NC}"
    read -p "Press Enter to return to menu..."
}

node_action_menu() {
    local node_name="$1"
    local node_ip="$2"
    
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== Node Rescue: ${node_name} ===${NC}"
        
        # Run Diagnosis first (disable set -e to handle return codes like 99)
        set +e
        perform_diagnosis "$node_name" "$node_ip"
        local diag_code=$?
        set -e
        alert_sound # Alert user (Ready for input)

        echo -e "\n${BOLD}Available Actions:${NC}"
        echo -e "1. ${RED}Emergency Hard Reboot (RESET)${NC}"
        echo -e "2. ${MAGENTA}Deep Forensics (Previous Boot Logs)${NC} - Use after reboot"
        echo -e "3. ${CYAN}Live Forensics (Current Boot Logs)${NC} - If node is reachable"
        echo -e "4. ${YELLOW}Serial Console Logs (Boot History)${NC} - ${BOLD}Run this if stuck in Reboot Loop!${NC}"
        echo -e "5. ${GREEN}Whitelist My IP (Fix SSH Block)${NC} - ${BOLD}Add rule to OCI Security List${NC}"
        echo -e "0. Back to Node List"
        
        echo -ne "\nSelect option: "
        read -r choice
        
        case "$choice" in
            5)
                echo -e "\n${CYAN}Attempting to whitelist your IP...${NC}"
                local ocid=$(get_instance_ocid_by_name "$node_name")
                if whitelist_my_ip "$ocid"; then
                    echo -e "${GREEN}Success! You should now be able to SSH.${NC}"
                    alert_sound
                else
                    echo -e "${RED}Failed to whitelist IP.${NC}"
                    echo -e "\a"
                fi
                echo "Press Enter to continue..."
                read
                ;;
            1)
                echo -e "\n${RED}${BOLD}!!! DANGER ZONE !!!${NC}"
                echo -e "Action: FORCE RESET (Power Cycle)"
                echo -e "Target: $node_name ($node_ip)"
                echo -e "Impact: RAM cleared. Unsaved data lost. **DATA ON DISK IS SAFE**."
                echo -e "-------------------------------------------------------------"
                
                read -p "Type 'REBOOT' to confirm execution: " confirm
                if [[ "$confirm" == "REBOOT" ]]; then
                    echo -e "${RED}Initiating Sequence...${NC}"
                    local ocid=$(get_instance_ocid_by_name "$node_name")
                    reboot_instance "$ocid" "RESET"
                    echo -e "${GREEN}Command Sent to OCI!${NC}"
                    echo -e "Waiting for node to cycle..."
                    sleep 10
                else
                    echo "Cancelled."
                    sleep 1
                fi
                ;;
            2)
                post_reboot_forensics "$node_name" "$node_ip"
                ;;
            3)
                echo -e "\n${CYAN}Pulling logs from CURRENT session (SSH)...${NC}"
                if ssh -q -o StrictHostKeyChecking=accept-new "$node_ip" "exit" 2>/dev/null; then
                    echo -e "---------------------------------------------------"
                    ssh -o StrictHostKeyChecking=no "$node_ip" "sudo journalctl -n 50 --no-pager"
                    echo -e "---------------------------------------------------"
                    echo -e "${GREEN}Live logs retrieved.${NC}"
                else
                    echo -e "${RED}Node is unreachable via SSH. Cannot pull live logs.${NC}"
                    echo -e "Try Hard Reboot then 'Previous Boot Forensics'."
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                echo -e "\n${YELLOW}Requesting Serial Console Logs from OCI...${NC}"
                echo -e "This takes about 10-20 seconds to capture."
                local ocid=$(get_instance_ocid_by_name "$node_name")
                
                # Fetch Logs
                local console_log
                console_log=$(get_instance_console_history "$ocid")
                
                if [[ -z "$console_log" ]]; then
                    echo -e "${RED}Failed to retrieve console logs.${NC}"
                    echo -e "${YELLOW}Debug Info:${NC}"
                    cat /tmp/oci_capture_error.log 2>/dev/null
                else
                    alert_sound # Alert user (Success)
                    echo -e "${GREEN}Logs Retrieved! Displaying last 50 lines...${NC}"
                    echo -e "---------------------------------------------------"
                    echo "$console_log" | tail -n 50
                    echo -e "---------------------------------------------------"
                    
                    # Option to save
                    echo -e "\nAlso saving full log to: $(pwd)/../../logs/console-${node_name}.log"
                    echo "$console_log" > "../../logs/console-${node_name}.log"
                    
                    echo -e "${CYAN}Tip: Look for specific services failing to start (e.g., 'Started Kubernetes Node Agent' ... HANG).${NC}"
                fi
                read -p "Press Enter to continue..."
                ;;
            0)
                return
                ;;
            *)
                echo "Invalid option."
                sleep 1
                ;;
        esac
    done
}

cloud_ops_menu() {
    while true; do
        clear
        echo -e "${BOLD}${CYAN}=== OCI Cloud Rescue Ops ===${NC}\n"
        
        # List Nodes with status place holder
        echo -e "${BOLD}Select Node to Diagnose/Rescue:${NC}"
        
        if ! nodes=$(run_kubectl "get nodes -o wide --no-headers" 2>/dev/null | awk '{print $1, $6}'); then
             # Fallback to OCI CLI if kubectl is down (Critical for Master Node rescue)
             alert_sound # Alert user
             echo -e "${YELLOW}Kubernetes API unreachable. Fetching form OCI...${NC}"
             local tenancy_id=$(get_tenancy_id)
             # Get list of DisplayName and PrivateIP
             # Note: This query assumes standard OCI VCN setups where primary IP is relevant
             # We filter for "k8s-" or "oci-k8s-" to avoid clutter if shared compartment
             nodes=$(oci compute instance list \
                --compartment-id "$tenancy_id" \
                --query "data[?contains(\"display-name\", 'k8s')].{\"name\":\"display-name\"}" \
                --raw-output 2>/dev/null | jq -r '.[].name' | while read -r name; do
                    # Simplified: We don't have easy IP access here without multiple calls, 
                    # so we just list the name. The diagnostics step resolves IP anyway.
                    # Strip 'oci-' prefix if present to match common naming convention in this script
                    short_name=${name#oci-}
                    echo "$short_name (OCI-Fallback)"
                done)
        fi
        
        # Use fzf to select (use FZF_BIN from parent or find in path)
        FZF_CMD="${FZF_BIN:-fzf}"
        selected=$(echo "$nodes" | $FZF_CMD --height 40% --layout=reverse --header="Select Node for Cloud Ops")
        
        if [[ -z "$selected" ]]; then
            return
        fi
        
        node_name=$(echo "$selected" | awk '{print $1}')
        node_ip=$(echo "$selected" | awk '{print $2}')
        
        node_action_menu "$node_name" "$node_ip"
    done
}
