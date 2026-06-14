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
        
    # Priority 2.5: High CPU Warning (OS Alive, K8s Ready/Unknown, but CPU High)
    elif [[ "$ssh_ok" == "true" && "$cloud_zombie" == "false" ]]; then
         # Check if CPU > 80
         # Remove the % sign and parens to compare
         local cpu_val=$(echo "$cpu_metric" | grep -oE "[0-9.]+" | head -n 1 | awk '{print int($1)}')
         if [[ "$cpu_val" -gt 80 ]]; then
             echo -e "${YELLOW}${BOLD}⚠️  WARNING: HIGH CPU LOAD DETECTED ($cpu_metric)${NC}"
             echo -e "${YELLOW}Node is responsive, but under heavy stress. Check 'Resource Usage'.${NC}"
             return 2
         else
             echo -e "${GREEN}Node appears HEALTHY.${NC}"
             return 0
         fi

    # Priority 3: Healthy (Fallback)
    else
        echo -e "${GREEN}Node appears HEALTHY.${NC}"
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
    
    # Define SSH Target using the Alias convention (reachable from Bastion/Public)
    local ssh_target="oci-$node_name"
    
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
        echo -e "6. ${MAGENTA}Resource Usage (Top Processes)${NC} - ${BOLD}Identify CPU/RAM Hogs${NC}"
        echo -e "7. ${CYAN}Auto-Fix Kubelet Typo${NC} - ${BOLD}Repair known 'override.conf' error${NC}"
        echo -e "8. ${YELLOW}Control Plane Health${NC} - ${BOLD}Inspect Kubelet, API & Etcd Logs${NC}"
        echo -e "9. ${RED}Hard Reset Control Plane${NC} - ${BOLD}Toggle Manifests to Fix Mirror Pods${NC}"
        echo -e "10. ${CYAN}Tune Etcd I/O Performance${NC} - ${BOLD}Fix Slow Disk/High CPU${NC}"
        echo -e "11. ${MAGENTA}Prioritize Control Plane${NC} - ${BOLD}Renice Etcd/API to High Priority${NC}"
        echo -e "12. ${YELLOW}Enforce API CPU Quota${NC} - ${BOLD}Lock API Server to 50% CPU${NC}"
        echo -e "13. ${RED}Surgical Rescue (Volume Fix)${NC} - ${BOLD}Detach Boot Vol -> Fix Files -> Restore${NC}"
        echo -e "0. Back to Node List"
        
        echo -ne "\nSelect option: "
        read -r choice
        
        case "$choice" in
            6)
                echo -e "\n${CYAN}Checking Resource Usage (top)...${NC}"
                echo -e "Connecting to $ssh_target..."
                # Run batch top, sort by CPU (default often is, but -o %CPU helps or just standard top)
                # Linux top: -b batch, -n 1 iteration, -o %CPU (if supported) or just head
                # standard top usually sorts by CPU by default.
                
                if ssh -q -o StrictHostKeyChecking=accept-new "$ssh_target" "top -b -n 1 | head -n 20"; then
                    echo -e "---------------------------------------------------"
                    echo -e "${GREEN}Snapshot Complete.${NC}"
                else
                    echo -e "${RED}Failed to SSH into node.${NC}"
                fi
                echo "Press Enter to continue..."
                read
                ;;
            7)
                echo -e "\n${MAGENTA}Attempting Live Repair of Kubelet Config...${NC}"
                echo -e "Target: $ssh_target"
                echo -e "Fixing known typo: '[Service]nMountFlags' -> '[Service]\nMountFlags'"
                
                # Check if file exists first
                if ssh -q -o StrictHostKeyChecking=accept-new "$ssh_target" "[ -f /etc/systemd/system/kubelet.service.d/override.conf ]"; then
                    # Perform the fix using sed
                    # We use a specific match to avoid breaking anything else
                     if ssh -q -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo sed -i 's/\[Service\]nMountFlags/\[Service\]\nMountFlags/g' /etc/systemd/system/kubelet.service.d/override.conf"; then
                         echo -e "${GREEN}File patched.${NC}"
                         
                         echo -e "Reloading systemd and restarting kubelet..."
                         if ssh -q -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo systemctl daemon-reload && sudo systemctl restart kubelet"; then
                             echo -e "${GREEN}Service Restarted!${NC}"
                             alert_sound
                         else
                             echo -e "${RED}Failed to restart service.${NC}"
                         fi
                     else
                         echo -e "${RED}Failed to patch file (sed error or permission).${NC}"
                     fi
                else
                    echo -e "${YELLOW}File /etc/systemd/system/kubelet.service.d/override.conf not found. Skipping.${NC}"
                fi
                echo "Press Enter to continue..."
                read
                ;;
            8)
                echo -e "\n${MAGENTA}Inspecting Control Plane Health...${NC}"
                echo -e "Target: $ssh_target"
                local timestamp=$(date +%Y%m%d_%H%M%S)
                local log_file="$CLOUD_DIR/../../../logs/cp-health-${node_name}-${timestamp}.log"
                mkdir -p "$(dirname "$log_file")"
                
                echo -e "\n${BOLD}1. Checking Kubelet Service Status:${NC}" | tee -a "$log_file"
                ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "systemctl status kubelet --no-pager -n 10" | tee -a "$log_file"
                
                echo -e "\n${BOLD}2. Identifying Control Plane Containers:${NC}" | tee -a "$log_file"
                ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo crictl ps --name 'kube-apiserver|etcd'" | tee -a "$log_file"
                
                echo -e "\n${BOLD}3. CAPTURING KUBE-APISERVER LOGS (Last 100 lines):${NC}" | tee -a "$log_file"
                local api_logs=$(ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo crictl logs --tail 100 \$(sudo crictl ps --name kube-apiserver -q | head -n 1)" 2>&1)
                echo "$api_logs" >> "$log_file"
                echo "(Saved to file)"
                
                echo -e "\n${BOLD}4. CAPTURING ETCD LOGS (Last 100 lines):${NC}" | tee -a "$log_file"
                local etcd_logs=$(ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo crictl logs --tail 100 \$(sudo crictl ps --name etcd -q | head -n 1)" 2>&1)
                echo "$etcd_logs" >> "$log_file"
                echo "(Saved to file)"
                
                echo -e "\n${CYAN}📥 Logs saved to: $log_file${NC}"

                # --- AUTO-ANALYSIS ---
                echo -e "\n${BOLD}🤖 RUNNING AUTOMATED ANALYSIS...${NC}"
                local analysis_found=false
                
                # Check Kube-Apiserver Patterns
                if echo "$api_logs" | grep -iEq "connection refused|dial tcp|i/o timeout"; then
                    echo -e "${RED}[!] API Server Network Issues Detected:${NC}"
                    echo "$api_logs" | grep -iEq "connection refused|dial tcp|i/o timeout" | tail -n 3
                    analysis_found=true
                fi
                if echo "$api_logs" | grep -iEq "etcdserver: request timed out"; then
                    echo -e "${RED}[!] Critical: API Server cannot talk to Etcd (High Latency/Timeouts)${NC}"
                    analysis_found=true
                fi
                if echo "$api_logs" | grep -iEq "throttling"; then
                     echo -e "${YELLOW}[!] Warning: API Server Throttling requests (Load Spike)${NC}"
                     analysis_found=true
                fi
                
                # Check Etcd Patterns
                if echo "$etcd_logs" | grep -iEq "database space exceeded"; then
                    echo -e "${RED}[!] CRITICAL: ETCD STORAGE FULL${NC}"
                    analysis_found=true
                fi
                 if echo "$etcd_logs" | grep -iEq "took too long"; then
                    echo -e "${YELLOW}[!] Warning: Etcd Disk I/O is slow (Heartbeat missed)${NC}"
                    analysis_found=true
                fi
                
                if [[ "$analysis_found" == "false" ]]; then
                    echo -e "${GREEN}No critical errors matched in recent logs.${NC}"
                    echo -e "Check the full log file manually."
                fi
                
                echo "Press Enter to continue..."
                read
                ;;
            9)
                echo -e "\n${RED}${BOLD}Performing Hard Reset of Control Plane (Manifest Toggle)...${NC}"
                echo -e "${YELLOW}This procedure stops Kubelet, moves static manifests to temp, waits for cleanup, and restores them.${NC}"
                echo -e "Target: $ssh_target"
                
                read -p "Type 'RESET' to confirm: " confirm_reset
                if [[ "$confirm_reset" == "RESET" ]]; then
                    echo -e "\n1. Stopping Kubelet..."
                    ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo systemctl stop kubelet"
                    
                    echo -e "2. Moving Manifests (Clearing State)..."
                    # Fix: Use bash -c so glob expansion (*.yaml) happens as root
                    ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo mkdir -p /tmp/k8s_manifests_bk && sudo bash -c 'mv /etc/kubernetes/manifests/*.yaml /tmp/k8s_manifests_bk/'"
                    
                    echo -e "3. Restarting Kubelet to Trigger Cleanup (Waiting 15s)..."
                    ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo systemctl start kubelet"
                    sleep 15
                    
                    echo -e "4. Stopping Kubelet again..."
                    ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo systemctl stop kubelet"
                    
                    echo -e "5. Restoring Manifests..."
                    # Fix: Use bash -c here too
                    ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo bash -c 'mv /tmp/k8s_manifests_bk/*.yaml /etc/kubernetes/manifests/'"
                    
                    echo -e "6. Final Restart of Kubelet..."
                    ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo systemctl start kubelet"
                    
                    echo -e "${GREEN}Reset Sequence Complete.${NC}"
                    echo -e "Wait 30-60 seconds for Control Plane to initialize, then check Health (Option 8)."
                    alert_sound
                else
                    echo "Cancelled."
                fi
                echo "Press Enter to continue..."
                read
                ;;
            10)
                echo -e "\n${CYAN}${BOLD}Tuning Etcd Performance for Slow Disk...${NC}"
                echo -e "Target: $ssh_target"
                echo -e "Goal: Increase Heartbeat to 1000ms and Election Timeout to 5000ms"
                
                # Check if already tuned
                if ssh -q -o StrictHostKeyChecking=accept-new "$ssh_target" "sudo grep -q 'heartbeat-interval=1000' /etc/kubernetes/manifests/etcd.yaml"; then
                     echo -e "${GREEN}Etcd is already tuned! No changes needed.${NC}"
                else
                     echo -e "Applying patch to /etc/kubernetes/manifests/etcd.yaml..."
                     
                     # We use sed to insert the flags after the 'command:' line or just before the image line if easier
                     # But safer is to append to the command arguments list.
                     # The arguments are typically:
                     #  - etcd
                     #  - --advertise-client-urls=...
                     # We can just append the lines after "- etcd"
                     
                     # Command: Find '- etcd' and append the new lines after it
                     local sed_cmd="sudo sed -i '/- etcd/a \    - --heartbeat-interval=1000\n    - --election-timeout=5000' /etc/kubernetes/manifests/etcd.yaml"
                     
                     if ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "$sed_cmd"; then
                         echo -e "${GREEN}Configuration Updated.${NC}"
                         echo -e "Etcd pod will restart automatically (wait 30s)..."
                         alert_sound
                     else
                         echo -e "${RED}Failed to patch manifest.${NC}"
                     fi
                fi
                echo "Press Enter to continue..."
                read
                ;;
            11)
                echo -e "\n${CYAN}${BOLD}Prioritizing Control Plane (CPU Scheduler)...${NC}"
                echo -e "Target: $ssh_target"
                echo -e "Goal: Renice Etcd (-10) and API Server (-5) to survive high load."
                
                # Command to find PIDs and renice
                # We use pgrep to find the processes by name
                
                echo -e "1. Boosting Etcd Priority..."
                if ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "pid=\$(pgrep etcd | head -n 1) && [ -n \"\$pid\" ] && sudo renice -n -10 -p \$pid"; then
                    echo -e "${GREEN}Etcd priority increased (Nice -10).${NC}"
                else
                    echo -e "${RED}Failed to renice Etcd (Process not found?)${NC}"
                fi

                echo -e "2. Boosting API Server Priority..."
                if ssh -o StrictHostKeyChecking=accept-new "$ssh_target" "pid=\$(pgrep kube-apiserver | head -n 1) && [ -n \"\$pid\" ] && sudo renice -n -5 -p \$pid"; then
                    echo -e "${GREEN}API Server priority increased (Nice -5).${NC}"
                else
                    echo -e "${RED}Failed to renice API Server.${NC}"
                fi
                
                alert_sound
                echo -e "${MAGENTA}Tip: This tells Linux to serve the Database FIRST, preventing timeouts.${NC}"
                echo "Press Enter to continue..."
                read
                ;;
            12)
                echo -e "\n${YELLOW}Enforcing CPU Quota on API Server...${NC}"
                echo -e "Target: $ssh_target"
                
                # Check if script exists on target, if not copy it
                scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
                    "${SCRIPT_DIR}/scripts/cloud_ops/cpu_quota_enforcer.sh" "${ssh_target}:/tmp/cpu_quota_enforcer.sh"
                
                ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null "$ssh_target" \
                    "sudo mv /tmp/cpu_quota_enforcer.sh /usr/local/bin/enforce_cpu_quota.sh && sudo chmod +x /usr/local/bin/enforce_cpu_quota.sh && sudo /usr/local/bin/enforce_cpu_quota.sh"
                    
                echo "Quota Enforcement Complete."
                read -p "Press Enter to continue..."
                ;;
            13)
                echo -e "\n${RED}${BOLD}!!! SURGICAL OPERATION !!!${NC}"
                echo -e "This procedure will STOP the node, detach its boot volume, fix the filesystem via a helper node, and restore it."
                echo -e "Patient: $node_name"
                echo -e "Doctor:  k8s-node-1 (Hardcoded default helper)"
                
                read -p "Type 'SURGERY' to confirm: " confirm_surgery
                if [[ "$confirm_surgery" == "SURGERY" ]]; then
                    # Call surgical script with Patient and Doctor
                    # Ensure we aren't operating on the doctor itself
                    if [[ "$node_name" == "k8s-node-1" ]]; then
                        echo -e "${RED}Cannot operate on the Doctor node itself! Choose another helper.${NC}"
                    else 
                        "$CLOUD_DIR/surgical_rescue.sh" "$node_name" "k8s-node-1"
                    fi
                else
                    echo "Cancelled."
                fi
                read -p "Press Enter to continue..."
                ;;
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
                if ssh -q -o StrictHostKeyChecking=accept-new "$ssh_target" "exit" 2>/dev/null; then
                    echo -e "---------------------------------------------------"
                    ssh -o StrictHostKeyChecking=no "$ssh_target" "sudo journalctl -n 50 --no-pager"
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
