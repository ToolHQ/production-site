#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper to run kubectl on master
run_kubectl_remote() {
  local cmd="$1"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -q "$MASTER_NODE" "kubectl $cmd"
}

# Helper to resolve K8s node name to SSH host alias
resolve_ssh_target() {
  local k8s_name="$1"
  # 1. Check if it matches a known node in common.sh NODES
  for n in "${NODES[@]}"; do
    if [[ "$n" == "$k8s_name" ]]; then
      echo "$n"
      return
    fi
  done
  # 2. Check for suffix match (e.g. oci-k8s-master matches k8s-master)
  for n in "${NODES[@]}"; do
    if [[ "$n" == *"$k8s_name" ]]; then
      echo "$n"
      return
    fi
  done
  # 3. Fallback: assume oci- prefix
  echo "oci-$k8s_name"
}

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}🛡️  Safe Node Update (OS & Kernel)${NC}"
echo -e "${BLUE}============================================================${NC}"

# 1. Pre-flight Check
echo "Checking cluster health..."
if ! run_kubectl_remote "get nodes" >/dev/null 2>&1; then
  echo -e "${RED}Error: Cannot talk to Kubernetes API (via $MASTER_NODE).${NC}"
  exit 1
fi

while true; do
  echo -e "\n${BLUE}--- Refreshing Node List ---${NC}"
  
  # 2. Gather Node Info (Serial for stability)
  echo "Fetching node details (Kernel, OS, Uptime)..."
  NODES_LIST=$(run_kubectl_remote "get nodes -o jsonpath='{.items[*].metadata.name}'" | tr ' ' '\n')

  # Create temp dir for results
  TMP_DIR=$(mktemp -d)
  # We don't trap EXIT here because we are in a loop, we clean up manually or let system handle /tmp
  
  # Format List for FZF
  # Header
  printf "%-20s | %-25s | %-30s | %-20s\n" "NODE" "KERNEL" "OS" "UPTIME" > "$TMP_DIR/list"
  printf "%-20s | %-25s | %-30s | %-20s\n" "----" "------" "--" "------" >> "$TMP_DIR/list"

  for node in $NODES_LIST; do
    # Resolve SSH target
    ssh_target=$(resolve_ssh_target "$node")
    
    # Fetch info via SSH
    # Output format: KERNEL|OS|UPTIME
    # Fix: Added quotes around the echo argument to prevent pipe interpretation
    if info=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$ssh_target" \
      "echo \"\$(uname -r)|\$(source /etc/os-release && echo \$PRETTY_NAME)|\$(uptime -p)\""); then
        
        IFS='|' read -r kernel os uptime <<< "$info"
        # Truncate OS string if too long
        os=$(echo "$os" | cut -c 1-30)
        printf "%-20s | %-25s | %-30s | %-20s\n" "$node" "$kernel" "$os" "$uptime" >> "$TMP_DIR/list"
    else
        printf "%-20s | %-25s | %-30s | %-20s\n" "$node" "UNREACHABLE" "N/A" "N/A" >> "$TMP_DIR/list"
    fi
  done

  # 3. Select Node
  # Check for FZF
  FZF_BIN="/tmp/k8s_ops_fzf"
  if [ ! -f "$FZF_BIN" ] && command -v fzf >/dev/null; then
    FZF_BIN=$(command -v fzf)
  fi

  TARGET_NODE=""
  if [ -x "$FZF_BIN" ]; then
    SELECTED_LINE=$(cat "$TMP_DIR/list" | "$FZF_BIN" --height=40% --layout=reverse --border --header-lines=2 --prompt="Select Node (ESC to exit) > ") || true
    TARGET_NODE=$(echo "$SELECTED_LINE" | awk '{print $1}')
  else
    echo "Select node to update (or Ctrl+C to exit):"
    select n in $NODES_LIST; do
      TARGET_NODE="$n"
      break
    done
  fi

  if [ -z "$TARGET_NODE" ]; then
    echo "Exiting..."
    rm -rf "$TMP_DIR"
    exit 0
  fi

  # Resolve SSH target for the selected node
  SSH_TARGET=$(resolve_ssh_target "$TARGET_NODE")

  echo -e "\n${YELLOW}Target Node:${NC} $TARGET_NODE (SSH: $SSH_TARGET)"

  # 4. Fetch Pending Updates & Release Status
  echo -e "\n${BLUE}Checking for available updates on $TARGET_NODE...${NC}"
  echo "Running 'apt-get update' to fetch latest lists..."

  # Run apt-get update
  if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$SSH_TARGET" \
       "sudo apt-get update >/dev/null 2>&1"; then
     echo -e "${YELLOW}⚠️  'apt-get update' failed (network or lock file issue). Using cached lists.${NC}"
  fi

  # Fetch updates info
  UPDATES_INFO=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$SSH_TARGET" \
    "apt list --upgradable 2>/dev/null" || echo "Error fetching updates")

  # Check for Release Upgrade (do-release-upgrade -c)
  # We check if the command exists and what it returns
  RELEASE_CHECK=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$SSH_TARGET" \
    "command -v do-release-upgrade >/dev/null && do-release-upgrade -c 2>&1" || echo "No upgrader")

  # Get Current OS Version for display
  CURRENT_OS=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$SSH_TARGET" \
    "lsb_release -d -s 2>/dev/null" || echo "Unknown OS")

  # Filter for interesting stuff
  KERNEL_UPDATES=$(echo "$UPDATES_INFO" | grep -i "linux-image" || true)
  TOTAL_UPDATES=$(echo "$UPDATES_INFO" | { grep -v "Listing..." || true; } | wc -l)

  echo -e "\n${CYAN}=== Pending Updates ===${NC}"
  if [ -n "$KERNEL_UPDATES" ]; then
    echo -e "${RED}🔥 KERNEL UPDATES AVAILABLE:${NC}"
    echo "$KERNEL_UPDATES"
  else
    echo -e "${GREEN}✅ No kernel updates found (for current OS release).${NC}"
  fi

  echo -e "\n📦 Total packages to upgrade: ${YELLOW}${TOTAL_UPDATES}${NC}"
  if [ "$TOTAL_UPDATES" -gt 0 ]; then
    echo "Top 10 updates:"
    echo "$UPDATES_INFO" | { grep -v "Listing..." || true; } | head -10
    if [ "$TOTAL_UPDATES" -gt 10 ]; then echo "... and $(($TOTAL_UPDATES - 10)) more"; fi
  fi

  # Show Release Upgrade Status
  UPDATE_MODE="standard"
  if echo "$RELEASE_CHECK" | grep -q "New release"; then
    # Extract new version from string like "New release '22.04.1 LTS' available."
    NEW_VERSION=$(echo "$RELEASE_CHECK" | grep "New release" | sed -E "s/.*'([^']+)'.*/\1/")
    
    echo -e "\n${RED}🚀 DISTRIBUTION UPGRADE AVAILABLE:${NC}"
    echo "$RELEASE_CHECK"
    echo -e "${YELLOW}Your OS is outdated. You can upgrade to a newer Ubuntu version.${NC}"
    
    echo -e "\nSelect Update Mode:"
    echo "1) Standard Update (apt-get dist-upgrade) - Keeps current OS ($CURRENT_OS)"
    echo "2) Full Release Upgrade (do-release-upgrade) - Upgrades OS ($CURRENT_OS -> $NEW_VERSION)"
    read -p "Choose (1/2): " mode_choice
    
    if [ "$mode_choice" == "2" ]; then
      UPDATE_MODE="release"
    fi
  else
    echo -e "\n${GREEN}No distribution release upgrade available.${NC}"
  fi

  # 5. Safety Confirmation
  echo -e "\n${RED}⚠️  WARNING: This process will:${NC}"
  echo "  1. Cordon the node (Prevent new pods)"
  echo "  2. Drain the node (Evict running pods - deletes emptyDir data)"
  if [ "$UPDATE_MODE" == "release" ]; then
    echo -e "  3. ${RED}RUN FULL OS RELEASE UPGRADE${NC} (Interactive - DO NOT CLOSE TERMINAL)"
  else
    echo "  3. Run 'apt-get dist-upgrade' (Apply ALL updates)"
  fi
  echo "  4. Reboot if required"
  echo "  5. Uncordon the node"
  echo ""
  read -p "Are you sure you want to proceed? (type 'yes'): " confirm

  if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    continue
  fi

  # 6. Cordon
  echo -e "\n${BLUE}1. Cordoning node...${NC}"
  run_kubectl_remote "cordon $TARGET_NODE"

  # 7. Drain
  echo -e "\n${BLUE}2. Draining node...${NC}"
  echo "   (This may take a while if pods have long termination grace periods)"
  echo -e "   ${YELLOW}Note: You may see 'Cannot evict pod' errors due to PDBs (e.g. Longhorn). This is normal, kubectl will retry.${NC}"
  
  # Drain loop to handle failures/retries
  while true; do
    # We run drain interactively via SSH to see output, but wrapped to handle errors
    # Added --timeout=180s to prevent infinite hangs
    if ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$MASTER_NODE" \
         "kubectl drain $TARGET_NODE --ignore-daemonsets --delete-emptydir-data --force --timeout=60s"; then
      echo -e "${GREEN}Drain successful.${NC}"
      break
    else
      echo -e "\n${RED}Drain failed or timed out!${NC}"
      echo "Options:"
      echo "  r) Retry Drain"
      echo "  f) Force Delete Pods (Bypasses PDBs - Risk of downtime)"
      echo "  i) Ignore & Continue (Update anyway)"
      echo "  a) Abort (Uncordon & Exit)"
      read -p "Choose action: " drain_action
      
      case "$drain_action" in
        r|R)
          echo "Retrying drain..."
          continue
          ;;
        f|F)
          echo -e "${RED}Force deleting all non-DaemonSet pods on $TARGET_NODE...${NC}"
          # Get all pods on the node (excluding DaemonSets ideally, but field-selector nodeName gets all)
          # We'll just delete all pods on the node. K8s will recreate them elsewhere.
          # Using remote kubectl to delete
          run_kubectl_remote "get pods --all-namespaces --field-selector spec.nodeName=$TARGET_NODE --no-headers -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name | xargs -r -n2 kubectl delete pod --force --grace-period=0 -n"
          echo "Pods deleted. Retrying drain to ensure clean state..."
          continue
          ;;
        i|I)
          echo "Ignoring drain failure. Proceeding with update..."
          break
          ;;
        *)
          echo "Aborting. Uncordoning node..."
          run_kubectl_remote "uncordon $TARGET_NODE"
          continue 2 # Continue outer loop (back to menu)
          ;;
      esac
    fi
  done

  # 8. Update
  echo -e "\n${BLUE}3. Performing Update ($UPDATE_MODE)...${NC}"

  if [ "$UPDATE_MODE" == "release" ]; then
    echo -e "${RED}⚠️  STARTING RELEASE UPGRADE. FOLLOW ON-SCREEN INSTRUCTIONS.${NC}"
    echo -e "${YELLOW}If asked about sshd configuration, choose 'keep local version' or default.${NC}"
    echo -e "${YELLOW}The session runs inside 'screen' usually. If disconnected, try to reconnect.${NC}"
    sleep 3
    
    # Interactive SSH for do-release-upgrade
    # We allow exit code 255 (SSH disconnect) because reboot kills the connection
    ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" \
        "sudo do-release-upgrade" || true
        
    echo -e "\n${BLUE}Release upgrade session ended.${NC}"
    # Force reboot check to YES because release upgrade usually reboots or requires it
    NEEDS_REBOOT="yes"
    
  else
    run_remote_stream "$SSH_TARGET" 'sudo apt-get dist-upgrade -y && sudo apt-get autoremove -y'
    # 9. Reboot Check (Standard)
    echo -e "\n${BLUE}4. Checking for reboot requirement...${NC}"
    NEEDS_REBOOT=$(run_remote_capture "$SSH_TARGET" "[ -f /var/run/reboot-required ] && echo 'yes' || echo 'no'")
  fi

  if [ "$NEEDS_REBOOT" == "yes" ]; then
    echo -e "${YELLOW}Reboot required (or performed). Waiting for $TARGET_NODE to come back...${NC}"
    
    # If standard update, we trigger the reboot. If release upgrade, it might have already happened.
    if [ "$UPDATE_MODE" == "standard" ]; then
       run_remote "$SSH_TARGET" "nohup sudo reboot >/dev/null 2>&1 &" || true
    fi
    
    echo "Waiting for node to go down (or be unreachable)..."
    sleep 10
    
    # Resolve SSH alias to real IP/Hostname for pinging
    # ssh -G prints configuration. We extract 'hostname'.
    REAL_HOST=$(ssh -G "$SSH_TARGET" | grep "^hostname " | awk '{print $2}')
    
    echo "Waiting for node to come back up (Ping check on $REAL_HOST)..."
    while ! ping -c 1 -W 1 "$REAL_HOST" >/dev/null 2>&1; do
      echo -n "."
      sleep 2
    done
    echo -e "\n${GREEN}Node is pingable.${NC}"
    
    echo "Waiting for SSH..."
    while ! ssh -o ConnectTimeout=2 -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$SSH_TARGET" "echo ready" >/dev/null 2>&1; do
      echo -n "."
      sleep 2
    done
    echo -e "\n${GREEN}SSH is ready.${NC}"
    
    echo "Waiting for Kubelet to be Ready..."
    while true; do
      STATUS=$(run_kubectl_remote "get node $TARGET_NODE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'")
      if [ "$STATUS" == "True" ]; then
        break
      fi
      echo -n "."
      sleep 2
    done
    echo -e "\n${GREEN}Kubelet is Ready.${NC}"
    
  else
    echo -e "${GREEN}No reboot required.${NC}"
  fi

  # 10. Uncordon
  echo -e "\n${BLUE}5. Uncordoning node...${NC}"
  run_kubectl_remote "uncordon $TARGET_NODE"

  echo -e "\n${GREEN}✅ Update complete for $TARGET_NODE${NC}"
  read -p "Press Enter to return to menu..."
  rm -rf "$TMP_DIR"
done
