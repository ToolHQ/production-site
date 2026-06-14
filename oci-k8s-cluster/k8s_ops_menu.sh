#!/usr/bin/env bash
set -euo pipefail

# Source common configuration for SSH keys and node info
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/lib/credstore.sh"
source "${SCRIPT_DIR}/lib/preferences.sh"
source "${SCRIPT_DIR}/lib/i18n.sh"

# Initialize preferences and set language
prefs_init
export I18N_LANG=$(prefs_get_language)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[1;30m'
NC='\033[0m' # No Color

# Fix for "Horrible Pink Background"
# Sets whiptail theme to Black/Grayscale + Cyan
export NEWT_COLORS='
root=,black
window=,black
border=white,black
shadow=,black
button=black,cyan
actbutton=black,cyan
compactbutton=,black
title=yellow,black
textbox=,black
acttextbox=black,cyan
entry=,black
disentry=gray,black
checkbox=,black
actcheckbox=black,cyan
listbox=,black
actlistbox=black,cyan
sellistbox=black,cyan
actsellistbox=black,cyan
'

# State variables
CURRENT_NS="default"
CURRENT_POD=""
FZF_BIN="/tmp/k8s_ops_fzf"
APP_DEPLOY_LAST_LOG_FILE=""
JSLIBS_NEXUS_PASSWORD=""

# WSL_DISTRO_NAME is only set by WSL on native terminal sessions.
# SSH sessions (e.g. via Tailscale) do not inherit it, causing `set -u` to abort.
# Resolve it here so all downstream code (Windows bridge / netsh UAC path) is safe.
if [[ -z "${WSL_DISTRO_NAME:-}" ]] && grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
    _wsl_exe="/mnt/c/Windows/System32/wsl.exe"
    if [[ -x "$_wsl_exe" ]]; then
        WSL_DISTRO_NAME=$(
            "$_wsl_exe" --list --running 2>/dev/null \
            | iconv -f UTF-16LE -t UTF-8 2>/dev/null \
            | tr -d '\r' \
            | grep -vE "^(Windows Subsystem|running distributions|-+|$)" \
            | head -1 \
            | sed 's/ (Default)//' \
            | xargs
        ) || true
    fi
    # Fallback: derive from /etc/os-release NAME (e.g. "Ubuntu")
    if [[ -z "${WSL_DISTRO_NAME:-}" ]]; then
        WSL_DISTRO_NAME=$(awk -F= '/^NAME=/{ gsub(/"/, "", $2); print $2 }' /etc/os-release 2>/dev/null) || true
    fi
    export WSL_DISTRO_NAME
fi
# Final safety net: ensure the variable is always defined (empty string) so set -u never aborts.
: "${WSL_DISTRO_NAME:=}"

# Returns true only when Windows UAC elevation via cmd.exe /c start is feasible.
# Requires: an interactive Windows desktop session (not available in SSH/headless).
_wsl_uac_available() {
    [[ -n "${WSL_DISTRO_NAME}" ]] && [[ -z "${SSH_CONNECTION:-}${SSH_CLIENT:-}" ]]
}

# --- FZF SETUP (Local) ---
ensure_fzf() {
  if command -v fzf >/dev/null 2>&1; then
    FZF_BIN=$(command -v fzf)
    return
  fi

  if [ -f "$FZF_BIN" ]; then
    return
  fi

  echo -e "${YELLOW}fzf not found locally. Downloading standalone binary to /tmp...${NC}"
  
  # Detect architecture
  ARCH=$(uname -m)
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  
  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) echo -e "${RED}Unsupported architecture: $ARCH${NC}"; exit 1 ;;
  esac

  # Download fzf
  FZF_VERSION="0.46.1"
  URL="https://github.com/junegunn/fzf/releases/download/${FZF_VERSION}/fzf-${FZF_VERSION}-${OS}_${ARCH}.tar.gz"
  
  curl -fsSL "$URL" -o /tmp/fzf.tar.gz
  tar -xzf /tmp/fzf.tar.gz -C /tmp
  mv /tmp/fzf "$FZF_BIN"
  chmod +x "$FZF_BIN"
  rm /tmp/fzf.tar.gz
  
  echo -e "${GREEN}fzf installed to $FZF_BIN${NC}"
  sleep 1
}

# --- K9S SETUP (Remote) ---
ensure_remote_k9s() {
  echo -e "${YELLOW}Checking for k9s on master node...${NC}"
  run_remote_stream "$MASTER_NODE" 'bash -euo pipefail <<'"'"'EOF'"'"'
    if command -v k9s >/dev/null 2>&1; then
      exit 0
    fi
    if [ -f /usr/local/bin/k9s ]; then
      exit 0
    fi
    
    echo "⬇️  k9s not found. Downloading..."
    ARCH=$(uname -m)
    case "$ARCH" in
      x86_64) ARCH="amd64" ;;
      aarch64|arm64) ARCH="arm64" ;;
    esac
    
    K9S_VERSION="v0.32.4"
    URL="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz"
    
    curl -fsSL "$URL" -o /tmp/k9s.tar.gz
    sudo tar -xzf /tmp/k9s.tar.gz -C /usr/local/bin k9s
    sudo chmod +x /usr/local/bin/k9s
    rm /tmp/k9s.tar.gz
    echo "✅ k9s installed."
EOF'
}

# --- HELPERS ---

run_kubectl() {
  local cmd="$1"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -q "$MASTER_NODE" "kubectl $cmd"
}

run_kubectl_silent() {
  local cmd="$1"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=5 -q "$MASTER_NODE" "kubectl $cmd" 2>/dev/null
}

run_interactive_ssh() {
  local cmd="$1"
  # Added || true to prevent script exit on Ctrl+C
  ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$MASTER_NODE" "kubectl $cmd" || true
}

open_url() {
  local url="$1"
  echo -e "${YELLOW}Attempting to open browser...${NC}"

  # Strategy 0: Windows Chrome (WSL specific) - User Priority
  if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null; then
    # Common Windows Chrome paths
    local chrome_paths=(
      "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe"
      "/mnt/c/Program Files (x86)/Google/Chrome/Application/chrome.exe"
      "/mnt/c/Users/$USER/AppData/Local/Google/Chrome/Application/chrome.exe"
      "/mnt/c/Users/$(whoami)/AppData/Local/Google/Chrome/Application/chrome.exe"
    )
    
    for cpath in "${chrome_paths[@]}"; do
      if [ -f "$cpath" ]; then
        echo "Found Windows Chrome at $cpath..."
        # Added --ignore-certificate-errors as requested
        "$cpath" --ignore-certificate-errors "$url" >/dev/null 2>&1 &
        return
      fi
    done

    # Fallback to cmd.exe start (Default Windows Browser)
    if command -v cmd.exe >/dev/null 2>&1; then
      echo "Using Windows Default Browser via cmd.exe..."
      cmd.exe /c start "" "$url" >/dev/null 2>&1
      return
    fi
  fi

  # Strategy 1: Explicit Linux Chrome/Chromium
  for browser in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "$browser" >/dev/null 2>&1; then
      echo "Found Linux $browser, opening..."
      "$browser" --ignore-certificate-errors "$url" >/dev/null 2>&1 &
      return
    fi
  done
  
  # Strategy 2: Python (Most reliable cross-platform)
  if command -v python3 >/dev/null 2>&1; then
    if python3 -m webbrowser "$url" >/dev/null 2>&1; then
      return
    fi
  fi
  
  # Strategy 3: xdg-open (Linux standard)
  if command -v xdg-open >/dev/null 2>&1; then
    echo "Trying xdg-open..."
    if xdg-open "$url"; then
      return
    fi
    echo -e "${RED}xdg-open failed.${NC}"
  fi
  
  # Strategy 4: wslview (WSL utility)
  if command -v wslview >/dev/null 2>&1; then
    echo "Trying wslview..."
    if wslview "$url"; then
      return
    fi
  fi
  
  # Strategy 5: open (macOS)
  if command -v open >/dev/null 2>&1; then
    echo "Trying open..."
    if open "$url"; then
      return
    fi
  fi
  
  # Fallback
  echo -e "${RED}Could not open browser automatically.${NC}"
  echo -e "Please copy the URL above and paste it into your browser."
}


format_age() {
    local diff=$1
    if [ "$diff" -lt 60 ]; then
        echo "${diff}s"
    elif [ "$diff" -lt 3600 ]; then
        echo "$((diff / 60))m"
    elif [ "$diff" -lt 86400 ]; then
        echo "$((diff / 3600))h"
    else
        echo "$((diff / 86400))d"
    fi
}

# --- ACTIONS ---

open_k9s() {
  ensure_remote_k9s
  echo -e "${GREEN}Launching k9s on master node...${NC}"
  # Run k9s remotely
  ssh -t -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      "$MASTER_NODE" "k9s" || true
}

open_dashboard() {
  echo -e "${BLUE}=== Opening Kubernetes Dashboard ===${NC}"
  
  # Clean helper
  capture_clean() {
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -q "$MASTER_NODE" "$1" 2>/dev/null
  }

  # --- AUTOMATION: SELF-HEALING ---
  # Source and run healing logic locally (since it uses kubectl commands that are likely wrapped or available via common.sh)
  # But wait, heal_dashboard.sh uses 'kubectl' directly. If we run it locally, does it have access?
  # The environment has kubeconfig. 
  # Let's ensure we source it properly.
  
  if [ -f "${SCRIPT_DIR}/scripts/observability/heal_dashboard.sh" ]; then
    source "${SCRIPT_DIR}/scripts/observability/heal_dashboard.sh"
    # We must ensure run_kubectl is available or kubectl is configured.
    # The menu runs locally and connects to master for some things, but also has kubectl configured locally in common.sh usually?
    # Actually checking common.sh/run_kubectl usage.
    # heal_dashboard.sh uses "kubectl". 
    # Let's wrap the call or just run it. 
    # If it fails, we ignore it.
    heal_dashboard || true
  fi
  # -------------------------------
  
  # 1. Get Token
  echo "Fetching admin token..."
  local token
  token=$(capture_clean "kubectl -n kubernetes-dashboard create token admin-user --duration=96h 2>/dev/null")
  
  if [ -z "$token" ]; then
    echo -e "${RED}Failed to get token. Is dashboard installed?${NC}"
    read -p "Press Enter..."
    return
  fi
  
  # 2. Check for Ingress (preferred) or fallback to ClusterIP
  echo "Resolving Dashboard URL..."
  local ingress_host
  ingress_host=$(capture_clean "kubectl -n kubernetes-dashboard get ingress -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null")
  
  local dashboard_url=""
  local local_port=""
  
  if [ -n "$ingress_host" ]; then
    # Use ingress
    echo -e "${GREEN}Using Ingress: https://$ingress_host${NC}"
    
    # Check if HTTPS port (443) is accessible locally
    if ! (lsof -iTCP:443 -sTCP:LISTEN &>/dev/null || ss -tulpn 2>/dev/null | grep -q ":443 "); then
      echo -e "${YELLOW}Port 443 not open locally. Opening ingress tunnel...${NC}"
      
      # Get ingress controller info
      local ingress_info
      ingress_info=$(detect_ingress_controller)
      
      if [ $? -eq 0 ]; then
        local ingress_ns=$(echo "$ingress_info" | cut -d'|' -f1)
        local ingress_name=$(echo "$ingress_info" | cut -d'|' -f2)
        local ports=$(echo "$ingress_info" | cut -d'|' -f3)
        
        # Extract HTTPS port
        local https_port=$(echo "$ports" | grep -o 'https:[0-9]*' | cut -d':' -f2)
        
        if [ -n "$https_port" ]; then
          # Use existing start_tunnel function
          start_tunnel "$ingress_ns" "$ingress_name" "443" "$https_port" "Ingress HTTPS" "true"
          echo -e "${GREEN}✅ Ingress tunnel opened on port 443${NC}"
        fi
      fi
    else
      echo -e "${GREEN}✅ Port 443 already accessible${NC}"
    fi
    
    dashboard_url="https://$ingress_host"
  else
    # Fallback to ClusterIP tunnel
    echo -e "${YELLOW}No ingress found, using local tunnel...${NC}"
    local cluster_ip
    cluster_ip=$(capture_clean "kubectl -n kubernetes-dashboard get svc kubernetes-dashboard-kong-proxy -o jsonpath='{.spec.clusterIP}'")
    
    if [ -z "$cluster_ip" ]; then
       # Fallback to old service name
       cluster_ip=$(capture_clean "kubectl -n kubernetes-dashboard get svc kubernetes-dashboard -o jsonpath='{.spec.clusterIP}'")
    fi

    if [ -z "$cluster_ip" ]; then
      echo -e "${RED}Failed to detect Dashboard ClusterIP.${NC}"
      read -p "Press Enter..."
      return
    fi
    
    echo "Target: $cluster_ip:443"
  
    # 3. Find available local port (starting from 8443)
    echo "Finding available local port..."
    local_port=$(find_available_port 8443)
    
    if [ "$local_port" != "8443" ]; then
        echo -e "${YELLOW}Port 8443 in use, using $local_port instead.${NC}"
    fi
    
    # 4. Start persistent background tunnel
    echo "Starting persistent tunnel..."
    ssh -f -N -L "$local_port:${cluster_ip}:443" \
        -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ExitOnForwardFailure=yes \
        "$MASTER_NODE"
  
    if [ $? -ne 0 ]; then
      echo -e "${RED}Failed to start tunnel.${NC}"
      read -p "Press Enter..."
      return
    fi
  
    # 5. Wait for tunnel
    echo "Waiting for tunnel to establish..."
    local retries=0
    while ! nc -z localhost "$local_port" > /dev/null 2>&1; do
      sleep 1
      ((retries++))
      if [ $retries -gt 10 ]; then
        echo -e "${RED}Timeout waiting for tunnel.${NC}"
        read -p "Press Enter..."
        return
      fi
    done
    
    # Save tunnel metadata
    mkdir -p "$TUNNEL_DIR"
    cat > "$TUNNEL_DIR/$local_port.meta" <<META
service=kubernetes-dashboard
namespace=kubernetes-dashboard
local_port=$local_port
remote_port=443
target=$cluster_ip
META
    
    dashboard_url="https://localhost:$local_port"
  fi
  
  # Display token
  echo ""
  echo "Token (Copied to clipboard if possible):"
  echo "$token"
  echo ""
  
  # Copy to clipboard
  if command -v clip.exe &> /dev/null; then
    echo -n "$token" | clip.exe
    echo "(Token copied to clipboard via clip.exe)"
  elif command -v xclip &> /dev/null; then
    echo -n "$token" | xclip -selection clipboard
    echo "(Token copied to clipboard via xclip)"
  elif command -v pbcopy &> /dev/null; then
    echo -n "$token" | pbcopy
    echo "(Token copied to clipboard via pbcopy)"
  else
    echo -e "${YELLOW}(Clipboard tool not found - please copy token manually)${NC}"
  fi
  
  # Final URL with navigation
  local full_url="${dashboard_url}/#/workloads?namespace=_all"
  echo ""
  echo "URL: $full_url"
  
  echo -e "\n${BLUE}Opening browser...${NC}"
  open_url "$full_url"
  
  # Only show tunnel message if using tunnel
  if [ -n "$local_port" ]; then
    echo -e "\n${GREEN}Dashboard tunnel running in background on port $local_port${NC}"
    echo "You can manage this tunnel via 'Access & Port Forwarding' -> 'Manage Active Tunnels'"
  fi
  read -p "Press Enter to return to menu..."
}

# --- MENUS ---

select_namespace() {
  echo "Fetching namespaces..."
  local ns_list
  ns_list=$(run_kubectl "get ns -o jsonpath='{.items[*].metadata.name}'" | tr ' ' '\n')
  
  if [ -z "$ns_list" ]; then
    echo -e "${RED}Error fetching namespaces.${NC}"
    return
  fi

  local selected
  selected=$(echo "$ns_list" | "$FZF_BIN" --height=60% --layout=reverse --border --prompt="Select Namespace (ESC to cancel) > " --header="Current: $CURRENT_NS") || true
  
  if [ -n "$selected" ]; then
    CURRENT_NS="$selected"
  fi
}

select_pod() {
  echo "Fetching pods in $CURRENT_NS..."
  
  # Get pod details in pipe-delimited format
  local pod_data
  pod_data=$(run_kubectl "-n $CURRENT_NS get pods --no-headers -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp")
  
  if [ -z "$pod_data" ]; then
    echo -e "${YELLOW}No pods found in namespace $CURRENT_NS.${NC}"
    read -p "Press Enter to continue..."
    return
  fi

  # Format with proper columns and header
  local formatted_pods=""
  while IFS= read -r line; do
    local name=$(echo "$line" | awk '{print $1}')
    local status=$(echo "$line" | awk '{print $2}')
    local ready=$(echo "$line" | awk '{print $3}')
    local restarts=$(echo "$line" | awk '{print $4}')
    local age_timestamp=$(echo "$line" | awk '{print $5}')
    
    # Calculate age from timestamp
    local age="N/A"
    if [ -n "$age_timestamp" ] && [ "$age_timestamp" != "<none>" ]; then
      local now=$(date +%s)
      local created=$(date -d "$age_timestamp" +%s 2>/dev/null || echo "$now")
      local diff=$((now - created))
      
      if [ $diff -lt 0 ]; then diff=0; fi
      age=$(format_age "$diff")
    fi
    
    # Format ready status
    if [ "$ready" = "true" ]; then
      ready="1/1"
    elif [ "$ready" = "false" ]; then
      ready="0/1"
    else
      ready="N/A"
    fi
    
    # Default restarts to 0 if empty
    [ -z "$restarts" ] || [ "$restarts" = "<none>" ] && restarts="0"
    
    formatted_pods+="$name|$status|$ready|$restarts|$age\n"
  done <<< "$pod_data"
  
  # Create header and format with column
  local header="NAME|STATUS|READY|RESTARTS|AGE"
  local display_data=$(echo -e "$header\n$formatted_pods" | column -t -s '|')
  
  # Use fzf with header
  local selected_line
  selected_line=$(echo "$display_data" | tail -n +2 | "$FZF_BIN" --height=70% --layout=reverse --border --prompt="Select Pod (ESC to go back) > " --header="$(echo "$display_data" | head -1)
Namespace: $CURRENT_NS") || true
  
  if [ -n "$selected_line" ]; then
    CURRENT_POD=$(echo "$selected_line" | awk '{print $1}')
    pod_actions_menu
  fi
}

pod_actions_menu() {
  while true; do
    local actions="1. Logs (tail -f)
2. Previous Logs
3. Describe
4. Exec (/bin/sh)
5. Exec (/bin/bash)
6. Delete (Restart)
0. Back"

    local selected_action
    selected_action=$(echo "$actions" | "$FZF_BIN" --height=50% --layout=reverse --border --prompt="Action for $CURRENT_POD > ") || true

    if [ -z "$selected_action" ]; then
      return
    fi

    case "${selected_action%%.*}" in
      1)
        clear
        echo -e "${YELLOW}Streaming logs for $CURRENT_POD (Ctrl+C to exit)...${NC}"
        run_interactive_ssh "-n $CURRENT_NS logs -f $CURRENT_POD"
        ;;
      2)
        clear
        echo -e "${YELLOW}Fetching previous logs...${NC}"
        run_interactive_ssh "-n $CURRENT_NS logs --previous $CURRENT_POD" || echo -e "${RED}No previous logs.${NC}"
        read -p "Press Enter..."
        ;;
      3)
        clear
        run_interactive_ssh "-n $CURRENT_NS describe pod $CURRENT_POD" | less
        ;;
      4)
        clear
        echo -e "${YELLOW}Connecting to /bin/sh...${NC}"
        run_interactive_ssh "-n $CURRENT_NS exec -it $CURRENT_POD -- /bin/sh"
        ;;
      5)
        clear
        echo -e "${YELLOW}Connecting to /bin/bash...${NC}"
        run_interactive_ssh "-n $CURRENT_NS exec -it $CURRENT_POD -- /bin/bash"
        ;;
      6)
        echo -e "${RED}WARNING: Deleting pod $CURRENT_POD${NC}"
        read -p "Are you sure? (y/N): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          run_kubectl "-n $CURRENT_NS delete pod $CURRENT_POD"
          echo -e "${GREEN}Pod deleted.${NC}"
          return
        fi
        ;;
      0)
        return
        ;;
    esac
  done
}

cluster_maintenance_menu() {
  while true; do
    local actions="$(t "maint_full_setup")
$(t "maint_full_heal")
$(t "maint_iptables")
$(t "maint_dns")
$(t "maint_network")
6. Clean Cluster Chaos (Evicted/Failed Pods)
7. Fix Registry DNS (Safe)
8. Prune Disk Space (Images/Logs)
9. Generate Storage Dossier (App-Level)
10. Pre-Pull Internal Images on All Nodes
11. Longhorn Headroom Diagnostic (T-307)
$(t "prefs_back")"

    local selected_action
    selected_action=$(echo "$actions" | "$FZF_BIN" --height=50% --layout=reverse --border --prompt="Maintenance > ") || true

    if [ -z "$selected_action" ]; then
      return
    fi

    case "${selected_action%%.*}" in
      1)
        clear
        echo -e "${BLUE}Running Full Cluster Setup/Repair...${NC}"
        ./setup_k8s_cluster.sh
        read -p "$(t "press_enter")"
        ;;
      2)
        clear
        echo -e "${RED}Running Full Cluster Heal (Nuclear)...${NC}"
        ./full_cluster_heal.sh
        read -p "$(t "press_enter")"
        ;;
      3)
        clear
        ./fix_iptables.sh
        read -p "$(t "press_enter")"
        ;;
      4)
        clear
        ./dns_doctor.sh
        read -p "$(t "press_enter")"
        ;;
      5)
        clear
        ./os_network_doctor.sh
        read -p "$(t "press_enter")"
        ;;
      6)
        clear
        source "$SCRIPT_DIR/scripts/maintenance/clean_cluster_chaos.sh"
        read -p "$(t "press_enter")"
        ;;
      7)
        clear
        source "$SCRIPT_DIR/scripts/maintenance/fix_registry_hosts.sh"
        read -p "$(t "press_enter")"
        ;;
      8)
        clear
        source "$SCRIPT_DIR/scripts/maintenance/prune_disk.sh"
        read -p "$(t "press_enter")"
        ;;
      9)
        clear
        source "$SCRIPT_DIR/scripts/observability/generate_storage_dossier.sh"
        read -p "$(t "press_enter")"
        ;;
      10)
        clear
        echo -e "${BLUE}Pre-Pull Internal Images on All Worker Nodes${NC}"
        echo -e "${YELLOW}This caches registry.local images so rescheduled pods start without Nexus.${NC}"
        echo ""
        # Discover internal images currently running in the cluster
        local internal_images
        internal_images=$(run_kubectl_silent "get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{\"\\n\"}{end}{end}'" | grep "registry.local" | sort -u)
        if [[ -z "$internal_images" ]]; then
          echo -e "${YELLOW}No pods using registry.local found.${NC}"
          read -p "$(t "press_enter")"; continue
        fi
        echo -e "${GREEN}Images to pre-pull:${NC}"
        echo "$internal_images"
        echo ""
        local worker_nodes
        worker_nodes=$(run_kubectl_silent "get nodes --no-headers -l '!node-role.kubernetes.io/control-plane'" | awk '{print $1}')
        echo -e "${GREEN}Worker nodes:${NC} $(echo $worker_nodes | tr '\n' ' ')"
        echo ""
        read -p "Proceed? (yes/no): " confirm
        [[ "$confirm" != "yes" ]] && continue
        local img node pod_name
        for img in $internal_images; do
          for node in $worker_nodes; do
            pod_name="prepull-$(echo "$node" | sed 's/k8s-//')-$$"
            echo -e "  Pulling ${img##*/} on $node..."
            run_kubectl "run $pod_name --image=$img --restart=Never \
              --overrides='{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"$node\"},\"tolerations\":[{\"operator\":\"Exists\"}]}}' \
              --command -- sh -c 'echo pulled' 2>/dev/null" || true
            # Wait up to 60s for completion
            local i=0
            while (( i < 12 )); do
              local phase
              phase=$(run_kubectl_silent "get pod $pod_name -o jsonpath='{.status.phase}'" 2>/dev/null)
              [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]] && break
              sleep 5; (( i++ ))
            done
            run_kubectl "delete pod $pod_name --ignore-not-found 2>/dev/null" || true
            echo -e "    ✅ Done on $node"
          done
        done
        echo ""
        echo -e "${GREEN}Pre-pull complete. Images are now cached on all worker nodes.${NC}"
        read -p "$(t "press_enter")"
        ;;
      11)
        clear
        bash "$SCRIPT_DIR/scripts/observability/longhorn_headroom_diag.sh"
        read -p "$(t "press_enter")"
        ;;
      *)
        return
        ;;
    esac
  done
}



component_management_menu() {
  while true; do
    local actions="1. Deploy/Update Components
2. Uninstall Components
3. $(t "comp_longhorn")
4. Global Registry Secret Repair (Fix Pull Errors)
$(t "prefs_back")"

    local selected_action
    selected_action=$(echo "$actions" | "$FZF_BIN" --height=50% --layout=reverse --border --prompt="Components > ") || true

    if [ -z "$selected_action" ]; then
      return
    fi

    case "${selected_action%%.*}" in
      1)
        clear
        ./deploy_components.sh
        read -p "$(t "press_enter")"
        ;;
      2)
        clear
        ./deploy_components.sh --uninstall
        read -p "$(t "press_enter")"
        ;;
      3)
        clear
        ./reinstall_longhorn.sh
        read -p "$(t "press_enter")"
        ;;
      3)
        clear
        echo -e "${CYAN}Generating Registry Secret Manifest...${NC}"
        
        # Define Script Path (Adjusted for location relative to SCRIPT_DIR)
        # Components are in the parent directory of oci-k8s-cluster (SCRIPT_DIR)
        SECRET_SCRIPT="$SCRIPT_DIR/../components/nexus/create_registry_secret.sh"
        
        if [ ! -f "$SECRET_SCRIPT" ]; then
             echo -e "${RED}Error: Script not found at $SECRET_SCRIPT${NC}"
             read -p "Press Enter..."
             return
        fi
        
        echo "---------------------------------------------------"
        # Run script: Stderr goes to terminal (logs), Stdout captured to variable
        echo "🌍 Targeting ALL namespaces..."
        YAML_OUTPUT=$("$SECRET_SCRIPT" "all")
        
        echo -e "\n${BOLD}Generated Manifest:${NC}"
        echo "$YAML_OUTPUT"
        echo "---------------------------------------------------"
        
        echo -e "\n${YELLOW}Do you want to APPLY this secret to the cluster?${NC}"
        read -p "Type 'APPLY' to confirm: " confirm_apply
        
        if [[ "$confirm_apply" == "APPLY" ]]; then
            # Save to local temp file
            echo "$YAML_OUTPUT" > /tmp/regsecret.yaml
            
            echo "Uploading manifest to master..."
            scp -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                /tmp/regsecret.yaml "$MASTER_NODE:/tmp/regsecret.yaml"
            
            echo "Applying manifest..."
            run_kubectl "apply -f /tmp/regsecret.yaml"
            
            echo -e "${GREEN}Secret Applied!${NC}"
            # Cleanup
            # run_kubectl "delete -f /tmp/regsecret.yaml 2>/dev/null" || true # REMOVED: This deleted the secret from cluster!
            ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$MASTER_NODE" "rm /tmp/regsecret.yaml"
            rm /tmp/regsecret.yaml
            
            alert_sound
        else
            echo "Cancelled."
        fi
        read -p "$(t "press_enter")"
        ;;

      0)
        return
        ;;
    esac
  done
}


# Tunnel Metadata Directory (stores service info for discovered tunnels)
TUNNEL_DIR="$HOME/.local/state/k8s_ops_tunnels"
TUNNEL_PIDS_FILE="$TUNNEL_DIR/active_pids.list"
mkdir -p "$TUNNEL_DIR"

# Find next available port starting from base_port
find_available_port() {
    local base_port=$1
    local allow_privileged="${2:-false}"
    local port=$base_port
    local max_attempts=100
    
    # For privileged ports (<1024), use mnemonic offset: 8000 + port
    # UNLESS allow_privileged is set to "true"
    if [ $port -lt 1024 ] && [ "$allow_privileged" != "true" ]; then
        port=$((8000 + base_port))
        # Only show warning if we are actually changing the port
        if [ "$port" != "$base_port" ]; then
             echo -e "${YELLOW}Note: Port $base_port requires root. Trying $port (8000+$base_port)...${NC}" >&2
        fi
    fi
    
    for ((i=0; i<max_attempts; i++)); do
        if ! lsof -i ":$port" >/dev/null 2>&1; then
            echo "$port"
            return 0
        fi
        ((port++))
    done
    
    echo "$base_port"  # Fallback to original if all attempts fail
    return 1
}

# Discover active SSH tunnels from system processes and enrich with metadata
discover_active_tunnels() {
    # Find SSH processes with LISTEN state (local port forwarding)
    # lsof output sample: ssh 347987 dnorio 4u IPv6 ... TCP [::1]:8443 (LISTEN)
    # Use sudo to detect tunnels on privileged ports (owned by root)
    local lsof_output=$(sudo lsof -i -P -n 2>/dev/null | grep -E '^ssh.*LISTEN' || true)
    
    if [ -z "$lsof_output" ]; then
        return 1
    fi
    
    # Parse lsof output to get PID, Bind IP, and Port
    # Column 2: PID, Column 9: NAME (e.g., "127.0.0.1:8443" or "[::1]:8443" or "127.0.0.2:5432")
    local tunnel_info=$(echo "$lsof_output" | awk '{
        # Extract IP and port from NAME column
        # Matches IP:PORT (IPv4) or [IPv6]:PORT
        if (match($9, /(.*):([0-9]+)/, arr)) {
            ip_str = arr[1]
            port = arr[2]
            
            # Remove brackets from IPv6
            gsub(/^\[|\]$/, "", ip_str)
            
            # Skip port 1 (SSH multiplexing control socket)
            if (port != "1") {
                print $2, ip_str, port
            }
        }
    }' | sort -u)
    
    if [ -z "$tunnel_info" ]; then
        return 1
    fi
    
    # Enrich with metadata
    while read -r pid bind_ip local_port; do
        [ -z "$pid" ] && continue
        
        # Use bind_ip-port as metadata key to match how we save it in start_tunnel
        local meta_key="${bind_ip//./-}-$local_port"
        local meta_file="$TUNNEL_DIR/$meta_key.meta"
        local service_info="Unknown Service"
        local namespace="unknown"
        
        local socat_pid=""
        local bridge_port=""
        
        if [ -f "$meta_file" ]; then
            # Read all metadata fields, including new Layer 2 info
            IFS='|' read -r m_svc m_ns m_name m_proto m_socat m_bridge < "$meta_file"
            service_info="$m_svc"
            namespace="$m_ns"
            local protocol="$m_proto"
            socat_pid="$m_socat"
            bridge_port="$m_bridge"
            
            # Append protocol to service_info for display
            if [ -n "$protocol" ] && [ "$protocol" != "unknown" ]; then
                service_info="$service_info [$protocol]"
            fi
        fi
        
        # Get remote port from process cmdline
        # Handle both formats: 127.0.0.1:PORT and IP:PORT bound
        local cmdline=$(ps -p "$pid" -o args= 2>/dev/null)
        local remote_port="unknown"
        
        # Try to extract port from -L argument (format: localport:host:remoteport or bind_ip:localport:host:remoteport)
        if [[ "$cmdline" =~ -L[[:space:]]+([^:]+:)?([0-9]+):([^:]+):([0-9]+) ]]; then
            # If 4 groups, means bind_ip is present. remote_port is the last group
             remote_port="${BASH_REMATCH[4]}"
        elif [[ "$cmdline" =~ :([0-9]+)$ ]]; then
             # simplistic fallback
             remote_port="${BASH_REMATCH[1]}"
        fi
        
        echo "$pid|$service_info|$namespace|$local_port|$remote_port|$bind_ip|$socat_pid|$bridge_port"
    done <<< "$tunnel_info"
}

start_tunnel() {
    local target_ns="${1:-}"
    local target_svc="${2:-}"
    local target_local_port="${3:-}"
    local target_remote_port="${4:-}"
    local target_desc="${5:-}"
    local force_port="${6:-false}"  # New parameter: force use of specific port
    local bind_ip="${7:-127.0.0.1}" # New parameter: bind ip (e.g. 127.0.0.2)
    local target_host="${8:-127.0.0.1}" # New parameter: remote target host (e.g. ClusterIP or PodIP)
    local no_prompt="${9:-false}"       # New parameter: skips "Press Enter" prompt

    local svc_info=""
    local desired_port=""
    local remote_port=""
    
    local allow_priv="$force_port"  # Use force_port to control privileged port enforcement
    
    # Interactive mode if no arguments provided
    if [ -z "$target_ns" ]; then
        echo -e "${BLUE}🔍 Discovering NodePort services...${NC}"
        
        local services
        services=$(run_kubectl "get svc -A --field-selector spec.type=NodePort -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {range .spec.ports[*]}{.name}:{.port}:{.nodePort} {end}{\"\\n\"}{end}'")
        
        if [ -z "$services" ]; then
          echo -e "${YELLOW}No NodePort services found.${NC}"
          read -p "Press Enter to return..."
          return
        fi

        # Get list of already-open ports from active tunnels (both remote NodePort and local port)
        local active_tunnel_data=$(discover_active_tunnels)
        local active_remote_ports=""
        local active_local_ports=""
        if [ -n "$active_tunnel_data" ]; then
            active_remote_ports=$(echo "$active_tunnel_data" | cut -d'|' -f5 | grep -v '^unknown$' | tr '\n' ' ')
            active_local_ports=$(echo "$active_tunnel_data" | cut -d'|' -f4 | tr '\n' ' ')
        fi

        local menu_items=""
        
        # 1. Add Postgres Smart Tunnels (Top Priority)
        # Fetch IPs dynamically
        local pg_0_ip=$(run_kubectl "-n postgres get pod postgres-0 -o jsonpath='{.status.podIP}'" 2>/dev/null || echo "")
        local pg_1_ip=$(run_kubectl "-n postgres get pod postgres-1 -o jsonpath='{.status.podIP}'" 2>/dev/null || echo "")
        
        if [ -n "$pg_0_ip" ]; then
             local status=""
             if [[ " $active_local_ports " == *" 5432 "* ]] && echo "$active_tunnel_data" | grep -q "postgres-0"; then
                 status=" [ACTIVE] ✓"
             fi
             menu_items+="postgres/postgres-0 (Primary: 127.0.0.2:5432 -> $pg_0_ip:5432) [SMART]$status\n"
        fi
         if [ -n "$pg_1_ip" ]; then
             local status=""
             if [[ " $active_local_ports " == *" 5432 "* ]] && echo "$active_tunnel_data" | grep -q "postgres-1"; then
                 status=" [ACTIVE] ✓"
             fi
             menu_items+="postgres/postgres-1 (Replica: 127.0.0.3:5432 -> $pg_1_ip:5432) [SMART]$status\n"
        fi
        
        # 2. Add NodePort Services
        while IFS= read -r line; do
          if [ -n "$line" ]; then
            local ns_name="${line%% *}"
            local ports_raw="${line#* }"
            local ports_display=""
            local has_active_tunnel=false
            
            for p in $ports_raw; do
                local p_name=$(echo "$p" | cut -d: -f1)
                local p_port=$(echo "$p" | cut -d: -f2)
                local p_nodeport=$(echo "$p" | cut -d: -f3)
                
                # Check if this NodePort already has an active tunnel
                local port_status=""
                if [[ " $active_remote_ports " == *" $p_nodeport "* ]] || [[ " $active_local_ports " == *" $p_port "* ]]; then
                    port_status=" ✓"
                    has_active_tunnel=true
                else
                    # Also check if service name matches any active tunnel
                    local svc_name="${ns_name##*/}"
                    if echo "$active_tunnel_data" | grep -q "$svc_name"; then
                        port_status=" ✓"
                        has_active_tunnel=true
                    fi
                fi
                
                ports_display+="$p_name: $p_port->$p_nodeport$port_status, "
            done
            ports_display="${ports_display%, }"
            
            # Add visual indicator if service has active tunnels
            if [ "$has_active_tunnel" = true ]; then
                menu_items+="$ns_name ($ports_display) [ACTIVE]\n"
            else
                menu_items+="$ns_name ($ports_display)\n"
            fi
          fi
        done <<< "$services"
        
        menu_items+="0. Back"

        local selected_item
        selected_item=$(echo -e "$menu_items" | "$FZF_BIN" --height=70% --layout=reverse --border --prompt="Start Tunnel > " --header="Select a service (✓ = already open)") || true

        if [ -z "$selected_item" ] || [[ "$selected_item" == "0. Back" ]]; then
          return
        fi

        # handle SMART selections immediately
        if [[ "$selected_item" == *"postgres/postgres-0"* ]] && [[ "$selected_item" == *"[SMART]"* ]]; then
             # start_tunnel ns svc local remote desc force bind target
             start_tunnel "postgres" "postgres-0" "5432" "5432" "Primary Tunnel" "true" "127.0.0.2" "$pg_0_ip"
             return
        fi
        if [[ "$selected_item" == *"postgres/postgres-1"* ]] && [[ "$selected_item" == *"[SMART]"* ]]; then
             start_tunnel "postgres" "postgres-1" "5432" "5432" "Replica Tunnel" "true" "127.0.0.3" "$pg_1_ip"
             return
        fi

        # Remove [ACTIVE] marker if present
        selected_item="${selected_item% [ACTIVE]}"
        
        svc_info="${selected_item%% *}"
        local namespace="${svc_info%%/*}"
        local service_name="${svc_info##*/}"
        local ports_info="${selected_item#* (}"
        ports_info="${ports_info%)}"


        local selected_port_mapping
        if [[ "$ports_info" == *", "* ]]; then
            local port_menu=$(echo "$ports_info" | sed 's/, /\n/g')
            selected_port_mapping=$(echo "$port_menu" | "$FZF_BIN" --height=20% --layout=reverse --border --prompt="Select Port > ") || true
        else
            selected_port_mapping="$ports_info"
        fi

        if [ -z "$selected_port_mapping" ]; then
            return
        fi

        # Remove ✓ marker if present
        selected_port_mapping="${selected_port_mapping% ✓}"
        
        desired_port=$(echo "$selected_port_mapping" | awk -F'->' '{print $1}' | awk -F': ' '{print $2}')
        remote_port=$(echo "$selected_port_mapping" | awk -F'->' '{print $2}')
    else
        # Non-interactive mode (arguments provided)
        svc_info="$target_ns/$target_svc"
        desired_port="$target_local_port"
        remote_port="$target_remote_port"
        # Define variables needed for protocol detection later
        local namespace="$target_ns"
        local service_name="$target_svc"
        
        # In non-interactive mode (e.g. Ingress menu), we trust the requested port
        # If force_port is already true (from parameter), keep it. Otherwise check if privileged port.
        if [ "$force_port" != "true" ] && [ "$desired_port" -le 1024 ]; then
            allow_priv="true"
        fi
        
        if [ -n "$target_desc" ]; then
            echo -e "${BLUE}Starting $target_desc...${NC}"
        fi
    fi

    
    if ! [[ "$desired_port" =~ ^[0-9]+$ ]] || ! [[ "$remote_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error parsing ports ($desired_port -> $remote_port).${NC}"
        read -p "Press Enter..."
        return
    fi

    # Auto-select available port
    local local_port=""
    
    if [ "$allow_priv" == "true" ]; then
        echo -e "${BLUE}Enforcing use of port $desired_port...${NC}"
        local_port="$desired_port"
        
        # Check and kill if in use on THIS SPECIFIC bind_ip
        # CRITICAL: Must check bind_ip:port, not just port, to avoid killing other loopback binds
        if sudo lsof -i "@$bind_ip:$local_port" > /dev/null 2>&1; then
             echo -e "${YELLOW}Port $bind_ip:$local_port is busy. Killing occupant...${NC}"
             local pids=$(sudo lsof -t -i "@$bind_ip:$local_port" -sTCP:LISTEN)
             if [ -n "$pids" ]; then
                 # Kill each PID individually (in case there are multiple)
                 for pid in $pids; do
                     sudo kill "$pid" 2>/dev/null || true
                 done
                 sleep 0.5  # Give it time to die
             fi
        fi
    else
        echo -e "${BLUE}Finding available local port (base: $desired_port)...${NC}"
        local_port=$(find_available_port "$desired_port" "$allow_priv")
        
        if [ "$local_port" != "$desired_port" ]; then
            echo -e "${YELLOW}Port $desired_port in use, using $local_port instead.${NC}"
        fi
    fi

    echo -e "${BLUE}Starting background tunnel for $svc_info ($bind_ip:$local_port -> $target_host:$remote_port)...${NC}"
    
    # Debug: Show exact bind IP being used
    echo -e "${GRAY}Bind IP: $bind_ip, Local Port: $local_port, Target: $target_host:$remote_port${NC}"
    
    # Check if we need sudo for privileged ports OR if bind_ip demands it (though usually only port < 1024 needs it)
    # However, binding to 127.0.0.1 usually fine. 127.0.0.2+ also usually fine on Linux.
    local use_sudo=""
    if [ "$local_port" -le 1024 ]; then
        echo -e "${YELLOW}⚠️  Port $local_port requires root privileges. You may be asked for your sudo password.${NC}"
        use_sudo="sudo"
    fi

    # Start SSH in background
    # We use 'sh -c' to properly handle the backgrounding with sudo if needed
    if [ -n "$use_sudo" ]; then
        # When running with sudo, we need to explicitly point to the user's SSH config
        # because root won't have the alias 'oci-k8s-master' defined.
        local ssh_config_opt=""
        if [ -f "$HOME/.ssh/config" ]; then
            ssh_config_opt="-F $HOME/.ssh/config"
        fi
        
        $use_sudo ssh $ssh_config_opt -i "$SSH_KEY" -f -N -L "$bind_ip:$local_port:$target_host:$remote_port" \
            -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ExitOnForwardFailure=yes \
            "$MASTER_NODE"
    else
        ssh -f -N -L "$bind_ip:$local_port:$target_host:$remote_port" \
            -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ExitOnForwardFailure=yes \
            "$MASTER_NODE"

    fi
    
        if [ $? -eq 0 ]; then
        echo -e "${GREEN}Tunnel started!${NC}"
        
        # Robust protocol detection with actual connectivity test using Bind IP
        local detected_protocol="tcp"
        echo -n "Detecting protocol... "
        sleep 1
        
        # Protocol check URLs
        local check_host="${bind_ip}"
        
        # Check if it's likely HTTPS (port 443, 8443, or service name contains 'dashboard', 'kong', 'ssl', 'tls')
        if [[ "$local_port" =~ ^(443|8443)$ ]] || [[ "$remote_port" =~ ^(443|31271)$ ]] || \
           [[ "$service_name" =~ (dashboard|kong|ssl|tls|secure) ]]; then
            # Test HTTPS first
            if curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "https://$check_host:$local_port" >/dev/null 2>&1; then
                detected_protocol="https"
                echo -e "${GREEN}HTTPS${NC}"
            elif curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://$check_host:$local_port" >/dev/null 2>&1; then
                detected_protocol="http"
                echo -e "${YELLOW}HTTP (expected HTTPS)${NC}"
            else
                detected_protocol="tcp"
                echo -e "${GRAY}TCP (no HTTP/HTTPS)${NC}"
            fi
        # Check for HTTP services
        elif [[ "$local_port" =~ ^(80|8080|8081|9000|9001)$ ]] || \
             [[ "$service_name" =~ (console|ui|web|api|nexus|minio|browser) ]]; then
            # Test HTTP first, then HTTPS
            if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://$check_host:$local_port" >/dev/null 2>&1; then
                detected_protocol="http"
                echo -e "${GREEN}HTTP${NC}"
            elif curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "https://$check_host:$local_port" >/dev/null 2>&1; then
                detected_protocol="https"
                echo -e "${YELLOW}HTTPS (expected HTTP)${NC}"
            else
                detected_protocol="tcp"
                echo -e "${GRAY}TCP (no HTTP/HTTPS)${NC}"
            fi
        # Default: TCP check for databases and other services
        else
            if nc -z "$check_host" "$local_port" >/dev/null 2>&1; then
                detected_protocol="tcp"
                echo -e "${GREEN}TCP${NC}"
            else
                detected_protocol="unknown"
                echo -e "${RED}No response${NC}"
            fi
        fi
        
        # Save metadata with detected protocol
        # CRITICAL: Use bind_ip-port as key to distinguish tunnels on same port but different loopback IPs
        local meta_key="${bind_ip//./-}-$local_port"
        echo "$svc_info|$namespace|$service_name|$detected_protocol" > "$TUNNEL_DIR/$meta_key.meta"
        
        # Display access URL with correct protocol
        local display_host="localhost"
        if [ "$check_host" != "127.0.0.1" ]; then
             display_host="$check_host"
        fi

        if [ "$detected_protocol" = "https" ]; then
            echo -e "Access URL: ${YELLOW}https://$display_host:$local_port${NC}"
        elif [ "$detected_protocol" = "http" ]; then
            echo -e "Access URL: ${YELLOW}http://$display_host:$local_port${NC}"
        else
            echo -e "Access URL: ${YELLOW}$display_host:$local_port${NC} (protocol: $detected_protocol)"
        fi
        
        # WINDOWS LOOPBACK BRIDGE (Double Bridge Strategy)
        # Goal: Allow Windows apps to connect to 127.0.0.X:5432
        # Flow: Windows App -> Windows 127.0.0.X:5432 (PowerShell Proxy) -> WSL IP:BridgePort -> socat -> WSL 127.0.0.X:local_port -> SSH Tunnel
        
        # Robust WSL Detection: Check /proc/version for "Microsoft" or "WSL"
        if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null && [ "$bind_ip" != "127.0.0.1" ]; then
            echo ""
            echo -e "${MAGENTA}WSL Detected + Custom Bind IP ($bind_ip). Initializing Windows Bridge...${NC}"
            
            # Check socat
            if ! command -v socat &>/dev/null; then
                 echo -e "${YELLOW}Installing socat for bridge support...${NC}"
                 sudo apt-get update -qq && sudo apt-get install -y socat >/dev/null 2>&1
            fi

            # Step 1: Bridge WSL Loopback -> WSL Interface (0.0.0.0) via socat on random high port
            local bridge_port=$(find_available_port "15432" "false")
            
            # Start socat bridge in background
            nohup socat -d -d TCP-LISTEN:$bridge_port,bind=0.0.0.0,fork TCP:$bind_ip:$local_port > /tmp/socat_${bind_ip}_${local_port}.log 2>&1 &
            local socat_pid=$!
            echo "$socat_pid" >> "$TUNNEL_PIDS_FILE"
            
            echo -e "${GRAY}  L2 (WSL): 0.0.0.0:$bridge_port -> $bind_ip:$local_port (PID: $socat_pid)${NC}"
            
            # Step 2: Bridge Windows Loopback -> WSL IP via PowerShell
            # Get WSL IP (as seen by Windows)
            local wsl_ip=$(hostname -I | awk '{print $1}')
            
            # Native Windows PortProxy (netsh)
            # Strategy: 
            # 1. Try running directly (Silent). Works if user is running WSL as Admin.
            # 2. If valid, fallback to RunAs (UAC Popup).
            
            local bridge_port="${bridge_port}"
            local win_bind_ip="${bind_ip}"
            local win_bind_port="${local_port}"
            local wsl_target_ip="127.0.0.1" # Windows sees WSL on localhost
            
            echo -e "${GRAY}  L3 (Win): Configuring Netsh Rule (${win_bind_ip}:${win_bind_port})...${NC}"
            
            # Silent Attempt
            # cd /mnt/c to avoid UNC warnings
            if (cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /c "netsh interface portproxy delete v4tov4 listenaddress=${win_bind_ip} listenport=${win_bind_port} & netsh interface portproxy add v4tov4 listenaddress=${win_bind_ip} listenport=${win_bind_port} connectaddress=${wsl_target_ip} connectport=${bridge_port}" >/dev/null 2>&1); then
                 echo -e "${GREEN}✅ Windows Bridge Activated (Silent Mode)!${NC}"
            else
                 # Fallback to UAC
                 echo -e "${YELLOW}  (Requires Admin) Triggering UAC prompt...${NC}"
                 local ps_runner="/tmp/netsh_runner_${win_bind_ip//./_}_${win_bind_port}.ps1"
            
                 cat <<EOF > "$ps_runner"
\$ErrorActionPreference = 'Stop'
\$bindIP = "${win_bind_ip}"
\$bindPort = "${win_bind_port}"
\$targetIP = "${wsl_target_ip}"
\$targetPort = "${bridge_port}"

# 1. Clear old rules to ensure clean state
netsh interface portproxy delete v4tov4 listenaddress=\$bindIP listenport=\$bindPort | Out-Null

# 2. Add new forwarding rule
# Maps Windows Loopback (e.g. 127.0.0.2:5432) -> WSL Bridge (127.0.0.1:BridgePort)
netsh interface portproxy add v4tov4 listenaddress=\$bindIP listenport=\$bindPort connectaddress=\$targetIP connectport=\$targetPort

Write-Host "✅ [Netsh] PortProxy Rule Added: \${bindIP}:\${bindPort} -> \${targetIP}:\${targetPort}" -ForegroundColor Green
Start-Sleep -Seconds 4
EOF
                 if _wsl_uac_available; then
                     /mnt/c/Windows/System32/cmd.exe /c start "Updating Network Rules" powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File \\\\wsl\$\\${WSL_DISTRO_NAME}${ps_runner}'"
                     echo -e "${GREEN}✅ Windows Bridge Activated via netsh!${NC}"
                 else
                     echo -e "${YELLOW}⚠️  UAC popup unavailable in SSH/headless session. Run this as Admin in Windows:${NC}"
                     echo -e "${CYAN}   netsh interface portproxy add v4tov4 listenaddress=${win_bind_ip} listenport=${win_bind_port} connectaddress=${wsl_target_ip} connectport=${bridge_port}${NC}"
                 fi
            fi

            echo -e "  You can now connect from Windows using: ${CYAN}${bind_ip}:${local_port}${NC}"
            
            # Update metadata with Layer 2 info for cleanup
            echo "$svc_info|$namespace|$service_name|$detected_protocol|$socat_pid|$bridge_port" > "$TUNNEL_DIR/$meta_key.meta"
        fi
    else
        echo -e "${RED}Failed to start tunnel.${NC}"
        return 1
    fi
    
    if [ "$no_prompt" != "true" ]; then
        read -p "Press Enter to continue..."
    fi
}

# --- INGRESS SUPPORT ---

detect_ingress_controller() {
    echo "$(t "ingress_detecting")" >&2
    # Try to find ingress-nginx-controller service in all namespaces
    local ingress_svc
    
    # 3. Parse info
    echo "$ingress_svc"
}

parse_ingress_data() {
    local raw_input="$1"
    # Logic to parse the specific format: namespace|name|portname:nodeport,
    # This helper is now testable purely with strings
    echo "$raw_input" | grep "ingress-nginx-controller|"
}

detect_ingress_controller() {
    # Try to find ingress-nginx-controller service in all namespaces (Silent)
    local raw_data
    # Use silent runner to avoid "kubectl get svc ..." print
    raw_data=$(run_kubectl_silent "get svc -A -o jsonpath='{range .items[*]}{@.metadata.namespace}{\"|\"}{@.metadata.name}{\"|\"}{range @.spec.ports[*]}{.name}{\":\"}{.nodePort}{\",\"}{end}{\"\\n\"}{end}'")
    
    local ingress_svc
    ingress_svc=$(parse_ingress_data "$raw_data")
    
    if [ -z "$ingress_svc" ]; then
        return 1
    fi
    
    echo "$ingress_svc"
}

get_ingress_hosts() {
    run_kubectl "get ingress -A -o jsonpath='{range .items[*]}{@.spec.rules[*].host}{\" \"}{end}'" | tr ' ' '\n' | sort | uniq | grep -v "^$"
}

manage_bridges() {
    while true; do
        clear
        echo -e "${BLUE}Fetching Windows Bridge Status (netsh)...${NC}"
        
        local status
        # Use tr to delete carriage returns and grep -a to handle binary garble from Windows cmd
        status=$(/mnt/c/Windows/System32/cmd.exe /c "netsh interface portproxy show v4tov4" 2>&1 | tr -d '\r')
        
        echo -e "\n${BOLD}=== LAYER 1: Windows Kernel Rules (netsh) ===${NC}"
        echo -e "${GRAY}(Windows Loopback -> WSL Bridge Port)${NC}"
        echo -e "Listen IP\tListen Port\tTarget IP\tTarget Port"
        echo -e "---------\t-----------\t---------\t-----------"
        
        # Parse netsh output for display
        echo "$status" | awk '/^[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1"\t"$2"\t\t"$3"\t"$4}'
        
        echo -e "\n${BOLD}=== LAYER 2: WSL Bridge Processes (socat) ===${NC}"
        echo -e "${GRAY}(WSL Bridge Port -> SSH Tunnel Endpoint)${NC}"
        
        local socat_list=""
        if pgrep -x "socat" >/dev/null; then
            echo -e "PID(s)\tBridge Port\tTarget Endpoint"
            echo -e "------\t-----------\t---------------"
            
            # Capture socat list for display AND selection
            # Deduplicate by Bridge Port
            while read -r line; do
                local pid=$(echo "$line" | awk '{print $1}')
                local listen=$(echo "$line" | grep -oP 'TCP-LISTEN:\K[0-9]+')
                local target=$(echo "$line" | grep -oP 'TCP:\K[^ ]+')
                
                if [ -n "$listen" ]; then
                    # Check if we already have this port in the list to avoid duplicate display rows for forks
                    if [[ ! "$socat_list" =~ "|$listen|" ]]; then
                        echo -e "${pid}..\t${listen}\t\t→ ${target}"
                        socat_list+="${pid}|${listen}|${target}\n"
                    fi
                fi
            done < <(pgrep -a socat | grep "TCP-LISTEN" | sort -k1n) # sort by PID
        else
            echo -e "${YELLOW}No active socat bridges found.${NC}"
        fi
         
        echo ""
        echo -e "${YELLOW}Note: Layer 1 'Target Port' should match Layer 2 'Bridge Port'.${NC}"
        echo ""
        echo -e "Press ${BOLD}[Enter]${NC} to return, or ${BOLD}[k]${NC} to Kill/Cleanup a Bridge."
        read -p "> " choice
        
        if [[ "$choice" == "k" ]] || [[ "$choice" == "K" ]]; then
            if [ -z "$socat_list" ]; then
                echo -e "${RED}No socat processes to kill.${NC}"
                sleep 1
                continue
            fi
            
            # Use FZF to select bridge to kill
            local selected
            selected=$(echo -e "$socat_list" | column -t -s '|' | "$FZF_BIN" --height=30% --layout=reverse --border --prompt="Select Bridge to Kill > " --header="PID  BridgePort  Target") || true
            
            if [ -n "$selected" ]; then
                local pid_kill=$(echo "$selected" | awk '{print $1}')
                local bridge_port_kill=$(echo "$selected" | awk '{print $2}')
                
                if [ -n "$bridge_port_kill" ]; then
                    echo -e "${YELLOW}Killing all socat processes for port $bridge_port_kill...${NC}"
                    # Kill all processes listening on this port (Parent + Forks)
                    pkill -f "TCP-LISTEN:$bridge_port_kill" 2>/dev/null
                    
                    # Find and Kill associated Netsh rule
                    
                    # Find and Kill associated Netsh rule
                    # Look for Netsh line where TargetPort ($4) matches our BridgePort
                    local netsh_match=$(echo "$status" | awk -v port="$bridge_port_kill" '$4 == port {print $1, $2}')
                    
                    if [ -n "$netsh_match" ]; then
                        local n_ip=$(echo "$netsh_match" | awk '{print $1}')
                        local n_port=$(echo "$netsh_match" | awk '{print $2}')
                        
                        echo -e "${YELLOW}Found orphan Netsh rule: $n_ip:$n_port -> ...:$bridge_port_kill${NC}"
                        echo -e "${YELLOW}Cleaning up Netsh rule...${NC}"
                        
                        # Silent Try
                        if (cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /c "netsh interface portproxy delete v4tov4 listenaddress=${n_ip} listenport=${n_port}" >/dev/null 2>&1); then
                            echo -e "${GREEN}✅ Rule Deleted (Silent)${NC}"
                        else
                             # Fallback UAC
                             local runner_del="/tmp/netsh_del_zombie_${n_ip//./_}_${n_port}.ps1"
                             cat <<EOF > "$runner_del"
\$ErrorActionPreference = 'Stop'
netsh interface portproxy delete v4tov4 listenaddress=${n_ip} listenport=${n_port} | Out-Null
Write-Host "✅ Rule Deleted: ${n_ip}:${n_port}" -ForegroundColor Green
Start-Sleep -Seconds 2
EOF
                             if _wsl_uac_available; then
                                 /mnt/c/Windows/System32/cmd.exe /c start "Cleaning Network Rules" powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File \\\\wsl\$\\${WSL_DISTRO_NAME}${runner_del}'"
                             else
                                 echo -e "${YELLOW}⚠️  UAC popup unavailable in SSH/headless session. Run this as Admin in Windows:${NC}"
                                 echo -e "${CYAN}   netsh interface portproxy delete v4tov4 listenaddress=${n_ip} listenport=${n_port}${NC}"
                             fi
                        fi
                    else
                        echo -e "${GRAY}No matching Netsh rule found for bridge port $bridge_port_kill.${NC}"
                    fi
                    
                    sleep 1
                fi
            fi
        else
            return
        fi
    done
}

ingress_menu() {
    while true; do
        clear
        echo -e "${BLUE} 🌐  $(t "ingress_menu_title") ${NC}"
        echo -e "${GRAY}────────────────────────────────────────${NC}"
        echo -e "${BLUE}🔍  Scanning cluster for Ingress Controller...${NC}"
        local ingress_info
        ingress_info=$(detect_ingress_controller)
        local status_icon="❌"
        
        if [ $? -eq 0 ]; then
            status_icon="✅"
            # Parse info: namespace|name|http:32xxx,https:32xxx,
            local ns=$(echo "$ingress_info" | cut -d'|' -f1)
            local name=$(echo "$ingress_info" | cut -d'|' -f2)
            local ports=$(echo "$ingress_info" | cut -d'|' -f3)
            
            # Formatted Output
            echo -e "${GREEN}✅  Found Ingress Controller${NC}"
            echo -e "    Namespace: ${CYAN}$ns${NC}"
            echo -e "    Service:   ${CYAN}$name${NC}"
            echo -e "    Ports:"
            
            # Split ports and display nicely
            echo "$ports" | sed 's/,/\n/g' | while read -r p; do
                if [ -n "$p" ]; then
                    local p_name=$(echo "$p" | cut -d':' -f1)
                    local p_port=$(echo "$p" | cut -d':' -f2)
                    # Align output
                    printf "      • %-10s : %s\n" "$p_name" "$p_port"
                fi
            done
        else
            echo -e "${RED}❌  No Ingress Controller found.${NC}"
        fi
        
        echo -e "${GRAY}────────────────────────────────────────${NC}"
        echo "1. Start Ingress Tunnel (All Ports) 🚀"
        echo "2. Update /etc/hosts (Ingress + Postgres) 📝"
        echo "3. Mobile Access via Tailscale 📱"
        echo "0. Back"
        echo ""
        read -p "$(t "choose_option") " choice
        
        case "$choice" in
            1)
                if [ -z "$ingress_info" ]; then
                    echo "$(t "ingress_not_found")"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                # Start tunnel for HTTP and HTTPS
                local http_port=$(echo "$ports" | grep -oP 'http:\K[0-9]+')
                local https_port=$(echo "$ports" | grep -oP 'https:\K[0-9]+')
                local postgres_port=$(echo "$ports" | grep -oP 'postgres:\K[0-9]+')
                
                # Fallback if named ports not found, try 80:xxxxx and 443:xxxxx logic if needed
                # But usually ingress-nginx uses http/https names.
                if [ -z "$http_port" ]; then
                     http_port=$(echo "$ports" | cut -d',' -f1 | cut -d':' -f2)
                fi
                if [ -z "$https_port" ]; then
                     https_port=$(echo "$ports" | cut -d',' -f2 | cut -d':' -f2)
                fi

                if [ -n "$http_port" ]; then
                    start_tunnel "$ns" "$name" "80" "$http_port" "Ingress HTTP" "true" "127.0.0.1" "127.0.0.1" "true"
                fi
                if [ -n "$https_port" ]; then
                    start_tunnel "$ns" "$name" "443" "$https_port" "Ingress HTTPS" "true" "127.0.0.1" "127.0.0.1" "true"
                fi
                
                # Also create TCP tunnel for MySQL if port is exposed AND DeepFlow is installed
                local mysql_port=$(echo "$ports" | grep -oP 'mysql:\K[0-9]+')
                if [ -n "$mysql_port" ] && run_kubectl_silent "get ns deepflow" >/dev/null 2>&1; then
                    echo -e "${BLUE}Creating MySQL TCP tunnel (local 3306 → remote $mysql_port)...${NC}"
                    start_tunnel "$ns" "$name" "3306" "$mysql_port" "DeepFlow MySQL" "true" "127.0.0.1" "$MASTER_NODE" "true"
                fi
                
                # Smart Postgres Tunneling (Primary + Replica)
                if [ -n "$postgres_port" ]; then
                    echo -e "${BLUE}Initializing Smart Postgres Tunnels...${NC}"
                    echo -e "${YELLOW}Initializing Robust Postgres Tunnels (HostNetwork Direct)...${NC}"
                    
                    # Fetch Node IPs for HostNetwork pods (Bypassing CNI Overlay)
                    # We run this remotely to get the correct internal IPs
                    PG0_IP=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$MASTER_NODE" "kubectl get pod -n postgres postgres-0 -o jsonpath='{.status.hostIP}' 2>/dev/null")
                    PG1_IP=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no "$MASTER_NODE" "kubectl get pod -n postgres postgres-1 -o jsonpath='{.status.hostIP}' 2>/dev/null")
                    
                    if [ -n "$PG0_IP" ]; then
                         # Forward to Node IP : 5432 (Since hostNetwork=true)
                         # 127.0.0.2:5432 -> Master -> PG0_NodeIP:5432
                         start_tunnel "postgres" "postgres-0" "5432" "5432" "Postgres Primary" "true" "127.0.0.2" "$PG0_IP" "true"
                    else
                         echo -e "${RED}Could not determine Node IP for postgres-0${NC}"
                    fi
                    
                    if [ -n "$PG1_IP" ]; then
                         # Forward to Node IP : 5432
                         # 127.0.0.3:5432 -> Master -> PG1_NodeIP:5432
                         start_tunnel "postgres" "postgres-1" "5432" "5432" "Postgres Replica" "true" "127.0.0.3" "$PG1_IP" "true"
                    else
                         echo -e "${RED}Could not determine Node IP for postgres-1${NC}"
                    fi
                else
                    echo -e "${YELLOW}PostgreSQL TCP port not found in Ingress Controller service${NC}"
                fi
                
                echo -e "${GREEN}$(t "ingress_tunnel_running")${NC}"
                
                # Auto-start Tailscale mobile access if tailscale0 is up
                local ts_ip
                ts_ip=$(ip -4 addr show tailscale0 2>/dev/null | grep -oP 'inet \K[0-9.]+')
                [ -z "$ts_ip" ] && ts_ip=$(tailscale ip -4 2>/dev/null)
                
                if [ -n "$ts_ip" ]; then
                    echo ""
                    echo -e "${BLUE}📱 Tailscale detected ($ts_ip) — starting mobile access...${NC}"
                    
                    # Mobile HTTPS tunnel (bind on Tailscale IP)
                    if ! ss -tln | grep -q "${ts_ip}:443"; then
                        start_tunnel "$ns" "$name" "443" "443" "Mobile HTTPS (Tailscale)" "true" "$ts_ip" "127.0.0.1" "true"
                    else
                        echo -e "${GREEN}  ✅ Mobile tunnel already active on ${ts_ip}:443${NC}"
                    fi
                    
                    # CoreDNS (auto-start if not running)
                    local coredns_dir
                    coredns_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tools/coredns" 2>/dev/null && pwd)"
                    if [ -d "$coredns_dir" ] && [ -x "$coredns_dir/start.sh" ]; then
                        if ! sudo ss -tulnp 2>/dev/null | grep -q "${ts_ip}:53"; then
                            echo -e "${BLUE}  🌐 Starting CoreDNS for *.dnor.io → ${ts_ip}${NC}"
                            sudo bash "$coredns_dir/start.sh" 53 2>&1 | grep -E "running|FAIL|ERROR" || true
                        else
                            echo -e "${GREEN}  ✅ CoreDNS already active on ${ts_ip}:53${NC}"
                        fi
                    fi
                    
                    echo -e "${GREEN}  📱 Mobile ready: https://*.dnor.io via Tailscale${NC}"
                fi
                
                read -p "$(t "press_enter")"
                ;;
            2)
                update_hosts_file
                ;;
            3)
                # Mobile access: HTTPS tunnel bound to Tailscale IP
                local ts_ip
                ts_ip=$(ip -4 addr show tailscale0 2>/dev/null | grep -oP 'inet \K[0-9.]+')
                if [ -z "$ts_ip" ]; then
                    ts_ip=$(tailscale ip -4 2>/dev/null)
                fi
                
                if [ -z "$ts_ip" ]; then
                    echo -e "${RED}❌ Tailscale not active — cannot find tailscale0 IP.${NC}"
                    echo "   Run: tailscale up"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                echo -e "${GREEN}📱 Tailscale IP: $ts_ip${NC}"
                
                if [ -z "$ingress_info" ]; then
                    echo "$(t "ingress_not_found")"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                local https_port
                https_port=$(echo "$ports" | grep -oP 'https:\K[0-9]+')
                if [ -z "$https_port" ]; then
                    https_port=$(echo "$ports" | cut -d',' -f2 | cut -d':' -f2)
                fi
                
                if [ -z "$https_port" ]; then
                    echo -e "${RED}❌ Could not detect HTTPS NodePort.${NC}"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                # Start tunnel: Tailscale_IP:443 → master:443
                echo -e "${BLUE}Starting HTTPS tunnel on ${ts_ip}:443 → $MASTER_NODE:443 ...${NC}"
                start_tunnel "$ns" "$name" "443" "443" "Mobile HTTPS (Tailscale)" "true" "$ts_ip" "127.0.0.1" "true"
                
                echo ""
                echo -e "${GREEN}✅ Mobile access ready!${NC}"
                echo -e "   Tunnel: ${CYAN}${ts_ip}:443${NC} → cluster ingress"
                echo ""
                echo -e "${YELLOW}📋 Next steps for your phone:${NC}"
                echo "   1. Tailscale must be active on your phone"
                echo "   2. Configure DNS (see option below) or add to /etc/hosts:"
                echo "      ${ts_ip}  coroot.dnor.io nexus.dnor.io k8s.dnor.io longhorn.dnor.io minio.dnor.io"
                echo "   3. Install the CA certificate on Android:"
                echo "      Settings → Security → Encryption & credentials → Install a certificate → CA certificate"
                echo "   4. Open https://coroot.dnor.io in Chrome"
                echo ""
                
                # Check if CoreDNS is already running
                if pgrep -f "coredns.*Corefile" >/dev/null 2>&1; then
                    echo -e "${GREEN}✅ CoreDNS is running — phone should resolve *.dnor.io automatically.${NC}"
                else
                    echo -e "${YELLOW}⚠️  CoreDNS not running. Phone will need manual /etc/hosts or Tailscale split DNS.${NC}"
                    echo "   To start CoreDNS: cd tools/coredns && ./start.sh"
                fi
                
                read -p "$(t "press_enter")"
                ;;
            0)
                return
                ;;
            *)
                echo "$(t "invalid_option")"
                sleep 1
                ;;
        esac
    done
}

update_hosts_file() {
    echo -e "${BLUE}Scanning Ingress hosts...${NC}"
    
    # Get all unique hosts from all Ingresses
    local ingress_hosts
    ingress_hosts=$(run_kubectl "get ingress -A -o jsonpath='{.items[*].spec.rules[*].host}'" | tr ' ' '\n' | sort -u | grep -v "^$")
    
    # Define Postgres mappings
    local pg_primary="postgres.dnor.io"
    local pg_replica="postgres-ro.dnor.io"
    
    local wsl_detected=false
    if grep -qEi "(Microsoft|WSL)" /proc/version; then
        wsl_detected=true
    fi

    echo -e "Found Ingress hosts:\n$ingress_hosts"
    echo -e "Adding Postgres mappings:"
    echo -e "  $pg_primary -> 127.0.0.2"
    echo -e "  $pg_replica -> 127.0.0.3"
    echo ""
    
    if [ "$wsl_detected" = true ]; then
        echo -e "${YELLOW}This will update BOTH your Linux (/etc/hosts) and Windows hosts files with ALL entries.${NC}"
    else
        echo -e "${YELLOW}This will add these hosts to your local /etc/hosts.${NC}"
    fi
    echo -e "${YELLOW}Root privileges (sudo/UAC) are required.${NC}"
    read -p "Do you want to proceed? (y/N) " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Build entries list for Linux /etc/hosts
        local linux_entries=""
        
        # Add Ingress hosts (127.0.0.1)
        for host in $ingress_hosts; do
            linux_entries+="127.0.0.1 $host\n"
        done
        
        # Add Postgres hosts (127.0.0.2, 127.0.0.3)
        linux_entries+="127.0.0.2 $pg_primary\n"
        linux_entries+="127.0.0.3 $pg_replica\n"
        
        # --- Update Linux Hosts ---
        echo -e "${BLUE}Updating Linux /etc/hosts...${NC}"
        
        local tmp_file=$(mktemp)
        echo -e "# Kubernetes Ingress Tunnels (dnor.io)" > "$tmp_file"
        echo -e "$linux_entries" >> "$tmp_file"
        
        # Aggressive Cleanup Strategy
        # Remove old block marker
        local marker="# Kubernetes Ingress Tunnels (dnor.io)"
        sudo sed -i "/$marker/d" /etc/hosts
        
        # Global removal for any dnor.io domain
        sudo sed -i '/\.dnor\.io/d' /etc/hosts
        
        # Append clean new block
        sudo bash -c "cat '$tmp_file' >> /etc/hosts"
        rm "$tmp_file"
        echo -e "${GREEN}Linux hosts updated!${NC}"
        
        # --- Update Windows Hosts (if WSL) ---
        if [ "$wsl_detected" = true ]; then
            echo ""
            echo -e "${BLUE}Updating Windows hosts file...${NC}"
            
            # Generate unique marker with timestamp for verification
            local timestamp=$(date +%s)
            local unique_marker="# Kubernetes Ingress Tunnels (dnor.io) - Updated: $timestamp"
            
            # PowerShell Script with OWNERSHIP TAKEOVER (nuclear option for antivirus)
            local ps_script="
\$hostsPath = \"\$env:SystemRoot\System32\drivers\etc\hosts\"
\$backupPath = \"\$hostsPath.bak\"
\$tempPath = \"\$env:TEMP\hosts_temp_\$(Get-Random).txt\"

Write-Host 'Creating backup...' -ForegroundColor Yellow
Copy-Item \$hostsPath \$backupPath -Force -ErrorAction SilentlyContinue

Write-Host 'Taking ownership of hosts file...' -ForegroundColor Yellow
& takeown.exe /F \$hostsPath
& icacls.exe \$hostsPath /grant Administrators:F

Write-Host 'Removing file protections...' -ForegroundColor Yellow
& cmd.exe /c \"attrib -r -s -h \$hostsPath\"

Write-Host 'Reading current hosts file...' -ForegroundColor Cyan
\$content = Get-Content \$hostsPath
\$newContent = @()
\$inBlock = \$false

foreach (\$line in \$content) {
    # Skip any existing Kubernetes block or dnor.io entries
    if (\$line -match 'Kubernetes.*Ingress.*Tunnels|dnor\.io') { 
        if (\$line -match '#.*Kubernetes') { \$inBlock = \$true }
        continue 
    }
    if (\$inBlock -and \$line.Trim() -eq '') { \$inBlock = \$false;continue }
    if (-not \$inBlock) { \$newContent += \$line }
}

Write-Host 'Adding new entries...' -ForegroundColor Cyan
\$newContent += \"\"
\$newContent += \"$unique_marker\"
$(for host in $ingress_hosts; do echo "\$newContent += \"127.0.0.1 $host\""; done)
\$newContent += \"127.0.0.2 $pg_primary\"
\$newContent += \"127.0.0.3 $pg_replica\"
\$newContent += \"\"

try {
    Write-Host 'Writing to temp file...' -ForegroundColor Yellow
    \$newContent | Out-File -FilePath \$tempPath -Encoding ASCII -Force
    
    Write-Host 'Replacing hosts file...' -ForegroundColor Yellow
    # Direct overwrite using Set-Content after ownership takeover
    \$newContent | Set-Content -Path \$hostsPath -Force -ErrorAction Stop
    
    Write-Host 'Windows hosts file updated successfully!' -ForegroundColor Green
} catch {
    Write-Error \"Failed: \$_\"
    Write-Host \"Restoring from backup...\" -ForegroundColor Yellow
    if (Test-Path \$backupPath) { 
        Copy-Item \$backupPath \$hostsPath -Force -ErrorAction SilentlyContinue
    }
    Write-Host \"ERROR: Antivirus is blocking file write. Please whitelist this script.\" -ForegroundColor Red
    exit 1
} finally {
    if (Test-Path \$tempPath) { Remove-Item \$tempPath -Force -ErrorAction SilentlyContinue }
}
Start-Sleep -Seconds 2
"
            echo "$ps_script" > "update_win_hosts.ps1"
            
            local win_script_path
            if command -v wslpath >/dev/null; then
                win_script_path=$(wslpath -w "./update_win_hosts.ps1")
            else
                win_script_path=".\\update_win_hosts.ps1"
            fi
            
            echo -e "${BLUE}Launching PowerShell as Admin...${NC}"
            powershell.exe -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"$win_script_path\"'" 2>&1 | tee /tmp/ps_output.log
            
            # Verify if the file was actually modified by checking for our marker
            echo -e "${GRAY}[DEBUG] Waiting for file sync...${NC}"
            sleep 2
            
            local verification_failed=false
            local win_hosts_mount="/mnt/c/Windows/System32/drivers/etc/hosts"
            
            echo -e "${GRAY}[DEBUG] Checking if Windows hosts mount exists: $win_hosts_mount${NC}"
            if [ -f "$win_hosts_mount" ]; then
                echo -e "${GRAY}[DEBUG] Mount found. Checking for timestamped marker...${NC}"
                echo -e "${GRAY}[DEBUG] Looking for: Updated: $timestamp${NC}"
                if grep -q "Updated: $timestamp" "$win_hosts_mount" 2>/dev/null; then
                    echo -e "${GREEN}[DEBUG] Timestamped marker found! Update successful.${NC}"
                    verification_failed=false
                else
                    echo -e "${RED}[DEBUG] Timestamped marker NOT found. Update failed!${NC}"
                    echo -e "${YELLOW}[DEBUG] Last 15 lines of Windows hosts file:${NC}"
                    tail -15 "$win_hosts_mount" 2>/dev/null || echo "[DEBUG] Could not read file"
                    verification_failed=true
                fi
            else
                echo -e "${YELLOW}[DEBUG] Mount not accessible. Cannot verify automatically.${NC}"
                echo -e "${YELLOW}Please check manually: C:\Windows\System32\drivers\etc\hosts${NC}"
                verification_failed=false  # Can't verify, assume it worked
            fi
            
            if [ "$verification_failed" = true ]; then
                echo -e "${RED}PowerShell automation failed (likely blocked by antivirus).${NC}"
                echo -e "${YELLOW}Opening Notepad for MANUAL editing...${NC}"
                
                # Create a temp file with instructions + entries to copy
                local instructions_file=$(mktemp /tmp/hosts_instructions.XXXXXX.txt)
                cat > "$instructions_file" <<EOF
==============================================
WINDOWS HOSTS FILE - MANUAL UPDATE REQUIRED
==============================================

Your antivirus blocked automatic editing.
Please follow these steps:

1. The Windows hosts file will open in Notepad (requires UAC approval)
2. Scroll to the bottom of the file
3. DELETE any existing "# Kubernetes Ingress Tunnels (dnor.io)" block
4. COPY the lines below and PASTE them at the end:

--- START COPYING HERE ---
# Kubernetes Ingress Tunnels (dnor.io)
$(for host in $ingress_hosts; do echo "127.0.0.1 $host"; done)
127.0.0.2 $pg_primary
127.0.0.3 $pg_replica

--- END COPYING HERE ---

5. Save the file (Ctrl+S)
6. Close Notepad

Press Enter in this terminal when done...
EOF
                # Show instructions in Linux terminal
                cat "$instructions_file"
                
                # Open Windows hosts in Notepad as Admin
                local win_hosts_win_path='C:\Windows\System32\drivers\etc\hosts'
                powershell.exe -Command "Start-Process notepad.exe -ArgumentList '$win_hosts_win_path' -Verb RunAs"
                
                read -p ""
                rm "$instructions_file"
                echo -e "${GREEN}Manual edit completed.${NC}"
            else
                echo -e "${GREEN}Windows hosts update completed.${NC}"
            fi
            rm "update_win_hosts.ps1"
        fi

    else
        echo "Cancelled."
    fi
    
    read -p "Press Enter..."
}


manage_tunnels() {
    # Helper for tunnel cleanup options
    perform_tunnel_cleanup() {
        local pid="$1"
        local lport="$2"
        local raw_bind="$3"
        local socat="$4"
        
        # 1. Kill SSH Tunnel
        if [ "$lport" -lt 1024 ]; then
            sudo kill "$pid" 2>/dev/null < /dev/null
        else
            kill "$pid" 2>/dev/null < /dev/null
        fi
        
        # 2. Kill Socat Process (Layer 2)
        if [ -n "$socat" ]; then
             echo -e "${YELLOW}Killing socat bridge (PID: $socat)...${NC}"
             kill "$socat" 2>/dev/null < /dev/null || true
        fi
        
        # 3. Delete Netsh Rule (Layer 1)
        if [ -n "$raw_bind" ] && [ "$raw_bind" != "127.0.0.1" ] && [ "$raw_bind" != "localhost" ]; then
            echo -e "${YELLOW}Deleting Windows netsh rule for $raw_bind:$lport...${NC}"
            
            # Silent Try (cd /mnt/c to fix UNC warnings)
            # Added < /dev/null to prevent stdin consumption
            if (cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /c "netsh interface portproxy delete v4tov4 listenaddress=${raw_bind} listenport=${lport}" >/dev/null 2>&1 < /dev/null); then
                echo -e "${GREEN}✅ Rule Deleted (Silent)${NC}"
            else
                # Fallback to UAC
                local runner_del="/tmp/netsh_del_${raw_bind//./_}_${lport}.ps1"
                cat <<EOF > "$runner_del"
\$ErrorActionPreference = 'Stop'
netsh interface portproxy delete v4tov4 listenaddress=${raw_bind} listenport=${lport} | Out-Null
Write-Host "✅ Rule Deleted: ${raw_bind}:${lport}" -ForegroundColor Green
Start-Sleep -Seconds 2
EOF
                # Run it
                # Added < /dev/null
                if _wsl_uac_available; then
                    /mnt/c/Windows/System32/cmd.exe /c start "Cleaning Network Rules" powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process powershell -Verb RunAs -ArgumentList '-ExecutionPolicy Bypass -File \\\\wsl\$\\${WSL_DISTRO_NAME}${runner_del}'" < /dev/null
                else
                    echo -e "${YELLOW}⚠️  UAC popup unavailable in SSH/headless session. Run this as Admin in Windows:${NC}"
                    echo -e "${CYAN}   netsh interface portproxy delete v4tov4 listenaddress=${raw_bind} listenport=${lport}${NC}"
                fi
            fi
        fi
        
        # Remove metadata file
        local meta_key="${raw_bind//./-}-$lport"
        [ -f "$TUNNEL_DIR/$meta_key.meta" ] && rm "$TUNNEL_DIR/$meta_key.meta"
        
        echo -e "${RED}Tunnel stopped (PID: $pid). Cleaned up associated bridges.${NC}"
    }

    while true; do
        echo -e "${BLUE}🔍 Scanning for active tunnels...${NC}"
        
        local tunnel_data=$(discover_active_tunnels)
        
        if [ -z "$tunnel_data" ]; then
            echo -e "${YELLOW}No active SSH tunnels found.${NC}"
            read -p "Press Enter to return..."
            return
        fi

        local menu_items=""
        # Add main menu option at the top
        menu_items="← Return to Main Menu\n⛔ Kill ALL Tunnels\n"
        
        while IFS='|' read -r pid svc_info namespace local_port remote_port bind_ip_raw socat_pid bridge_port; do
            # Format bind info if not 127.0.0.1
            local bind_display=""
            if [ -n "$bind_ip_raw" ] && [ "$bind_ip_raw" != "127.0.0.1" ] && [ "$bind_ip_raw" != "localhost" ]; then
                bind_display=" ($bind_ip_raw)"
            fi
            menu_items+="$svc_info (Local: $local_port$bind_display -> Remote: $remote_port) [PID: $pid]\n"
        done <<< "$tunnel_data"

        menu_items+="↩ Back to Access Menu"
        
        local selected
        selected=$(echo -e "$menu_items" | "$FZF_BIN" --height=70% --layout=reverse --border --prompt="Manage Tunnels (Select to Stop) > " --header="Active Tunnels") || true

        # Check what was selected
        if [ -z "$selected" ]; then
            return 1  # User cancelled, back to access menu
        elif [[ "$selected" == "← Return to Main Menu" ]]; then
            return 0  # Return to main menu
        elif [[ "$selected" == "↩ Back to Access Menu" ]]; then
            return 1
        elif [[ "$selected" == "⛔ Kill ALL Tunnels" ]]; then
            echo -e "${RED}Stopping ALL tunnels...${NC}"
            
            read -p "Are you sure? (y/N): " confirm_all
            if [[ "$confirm_all" =~ ^[Yy]$ ]]; then
                # Use FD 3 to prevent stdin stealing by inner commands
                while IFS='|' read -u 3 -r pid svc_info namespace local_port remote_port bind_ip_raw socat_pid bridge_port; do
                     perform_tunnel_cleanup "$pid" "$local_port" "$bind_ip_raw" "$socat_pid"
                done 3<<< "$tunnel_data"
                echo -e "${GREEN}All active tunnels stopped.${NC}"
                sleep 1.5
            else
                echo "Cancelled."
                sleep 1
            fi
            continue
        fi

        local pid_to_kill=$(echo "$selected" | grep -oP 'PID: \K[0-9]+')
        
        # Re-fetch full data line for this PID to get socat/bridge info (since fzf only showed summary)
        local selected_data=$(echo "$tunnel_data" | grep "^$pid_to_kill|")
        local raw_bind_ip=$(echo "$selected_data" | cut -d'|' -f6)
        local socat_pid=$(echo "$selected_data" | cut -d'|' -f7)
        local local_port=$(echo "$selected_data" | cut -d'|' -f4)
        
        if [ -n "$pid_to_kill" ]; then
            perform_tunnel_cleanup "$pid_to_kill" "$local_port" "$raw_bind_ip" "$socat_pid"
            sleep 1.0
        fi
    done
}

# --- SECURITY MENU ---
security_menu() {
    while true; do
        local menu="$(t "sec_check_certs")
$(t "sec_view_policies")
$(t "sec_audit_log")
$(t "sec_force_renew")
$(t "sec_export_ca")
$(t "sec_install_ca")
$(t "sec_rebuild_chains")
$(t "back")"

        local selected
        selected=$(echo "$menu" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Security > " --header="$(t "sec_menu_title")") || true

        if [ -z "$selected" ]; then
            return
        fi

        case "${selected%%.*}" in
            1)
                echo -e "${BLUE}📜 Fetching certificate status...${NC}"

                # Single SSH call: returns lines of "name|ns|notAfter|secret|chainCount"
                local raw_data
                raw_data=$(ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new \
                    -n -T "$MASTER_NODE" '
                    kubectl get certificates -A \
                      -o jsonpath='"'"'{range .items[*]}{.metadata.name}|{.metadata.namespace}|{.status.notAfter}|{.spec.secretName}{"\n"}{end}'"'"' 2>/dev/null \
                    | while IFS="|" read -r name ns not_after secret; do
                        count=$(kubectl get secret "$secret" -n "$ns" \
                          -o jsonpath='"'"'{.data.tls\.crt}'"'"' 2>/dev/null \
                          | base64 -d 2>/dev/null \
                          | grep -c "BEGIN CERTIFICATE" 2>/dev/null || echo 0)
                        echo "${name}|${ns}|${not_after}|${secret}|${count}"
                    done
                    ')

                echo -e "\033[1A\033[2K"  # clear "Fetching..." line
                echo ""
                printf "  ${BOLD}%-35s  %-10s  %-12s  %s${NC}\n" "CERT" "DAYS LEFT" "EXPIRES" "CHAIN"
                printf "  %s\n" "$(printf '─%.0s' {1..72})"

                local now_epoch
                now_epoch=$(date +%s)
                while IFS='|' read -r cert_name cert_ns not_after secret_name chain_count; do
                    [[ -z "$cert_name" ]] && continue
                    local exp_epoch days_left day_label chain_label
                    exp_epoch=$(date -d "$not_after" +%s 2>/dev/null || echo 0)
                    days_left=$(( (exp_epoch - now_epoch) / 86400 ))

                    if   (( days_left <  7 )); then day_label="${RED}${days_left}d 🔴${NC}"
                    elif (( days_left < 30 )); then day_label="${YELLOW}${days_left}d 🟡${NC}"
                    else                            day_label="${GREEN}${days_left}d 🟢${NC}"; fi

                    if (( chain_count >= 2 )); then chain_label="${GREEN}✔ OK${NC}"
                    else                          chain_label="${RED}✘ BROKEN (run opt 7)${NC}"; fi

                    # Short expires date: strip T and seconds
                    local expires_short="${not_after%%T*}"
                    printf "  %-35s  %-10b  %-12s  %b\n" \
                        "$cert_ns/$cert_name" "$day_label" "$expires_short" "$chain_label"
                done <<< "$raw_data"

                printf "  %s\n" "$(printf '─%.0s' {1..72})"
                echo ""
                echo -e "${BLUE}📜 Cluster Issuers:${NC}"
                run_kubectl "get clusterissuer"
                read -p "$(t "press_enter")"
                ;;
            2)
                echo -e "${BLUE}🛡️  Network Policies:${NC}"
                run_kubectl "get networkpolicy -A"
                read -p "$(t "press_enter")"
                ;;
            3)
                security_audit_menu
                ;;
            4)
                # Force Renew (Delete Certificate)
                echo -e "${BLUE}🔄 Select Certificate to Renew (Delete):${NC}"
                local certs
                certs=$(run_kubectl "get certificate -A --no-headers" | awk '{print $1 " " $2}')
                
                if [ -z "$certs" ]; then
                    echo "No certificates found."
                    sleep 2
                    continue
                fi
                
                local selected_cert
                selected_cert=$(echo "$certs" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Renew Cert > ") || true
                
                if [ -n "$selected_cert" ]; then
                    local ns=$(echo "$selected_cert" | awk '{print $1}')
                    local name=$(echo "$selected_cert" | awk '{print $2}')
                    
                    echo -e "${YELLOW}Deleting certificate $ns/$name to trigger renewal...${NC}"
                    run_kubectl "delete certificate -n $ns $name"
                    echo -e "${GREEN}Certificate deleted. Watch status in option 1.${NC}"
                    sleep 2
                fi
                ;;
            5)
                # Export Root CA (Selectable)
                echo -e "${BLUE}🔍 Fetching Cluster Issuers...${NC}"
                
                # Get list of ClusterIssuers (only those with a CA secret)
                local issuers
                issuers=$(run_remote_raw "$MASTER_NODE" "kubectl get clusterissuer -o jsonpath='{range .items[?(@.spec.ca.secretName)]}{.metadata.name}{\"\\n\"}{end}'")
                
                if [ -z "$issuers" ]; then
                    echo -e "${RED}❌ No exportable CA ClusterIssuers found.${NC}"
                    echo "   (Only issuers of type 'CA' with a configured secret can be exported)"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                # Select Issuer
                local selected_issuer
                selected_issuer=$(echo "$issuers" | tr ' ' '\n' | "$FZF_BIN" --height=20% --layout=reverse --border --prompt="Select Issuer > " --header="Choose which CA to export") || true
                
                if [ -z "$selected_issuer" ]; then
                    continue
                fi
                
                echo -e "${BLUE}👉 Selected: $selected_issuer${NC}"
                
                # Get Secret Name
                local secret_name
                secret_name=$(run_remote_raw "$MASTER_NODE" "kubectl get clusterissuer $selected_issuer -o jsonpath='{.spec.ca.secretName}' 2>/dev/null")
                
                if [ -z "$secret_name" ]; then
                    echo -e "${YELLOW}⚠️  This issuer ($selected_issuer) does not seem to have a CA secret (it might be ACME/Let's Encrypt).${NC}"
                    echo -e "   Only 'CA' type issuers have a downloadable root certificate."
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                echo -e "${BLUE}📥 Exporting CA from secret: $secret_name ...${NC}"
                
                if run_remote_stream "$MASTER_NODE" "kubectl -n cert-manager get secret $secret_name >/dev/null 2>&1"; then
                    # Use run_remote_raw for direct output (no logs in stdout)
                    # Fix: Add timeout to prevent hang if master is down (Zombie Master)
                    run_remote_raw "$MASTER_NODE" -o ConnectTimeout=5 "kubectl -n cert-manager get secret $secret_name -o jsonpath='{.data.ca\.crt}' | base64 -d" > "${selected_issuer}.crt"
                    
                    echo -e "${GREEN}✅ Certificate saved to: $(pwd)/${selected_issuer}.crt${NC}"
                    echo ""
                    echo -e "${YELLOW}👉 Manual import:${NC}"
                    echo "  Windows: Double-click > Install Certificate > Local Machine > Trusted Root Certification Authorities"
                    echo "  Chrome:  Settings > Privacy and security > Security > Manage certificates > Authorities > Import"
                    echo "  Linux:   Copy to /usr/local/share/ca-certificates/ and run 'update-ca-certificates'"
                    echo ""
                    read -p "$(echo -e "${BLUE}Install automatically on this machine now? [y/N]: ${NC}")" install_now
                    if [[ "${install_now,,}" == "y" ]]; then
                        # Inline install flow (same as option 6 but with the just-exported file)
                        local install_crt="${selected_issuer}.crt"
                        # WSL/Linux
                        if [ -d "/usr/local/share/ca-certificates" ]; then
                            sudo cp "$install_crt" "/usr/local/share/ca-certificates/$install_crt"
                            sudo update-ca-certificates
                            echo -e "${GREEN}✅ Installed in system CA store.${NC}"
                        fi
                        # Windows via certutil
                        if command -v cmd.exe >/dev/null 2>&1; then
                            echo -e "${BLUE}🪟 Installing on Windows (Trusted Root)...${NC}"
                            echo -e "${YELLOW}⚠️  You may see a Windows prompt asking for permission.${NC}"
                            local win_temp wsl_temp cert_win_path
                            win_temp=$(cmd.exe /c "echo %TEMP%" 2>/dev/null | tr -d '\r' || true)
                            if [ -n "$win_temp" ]; then
                                wsl_temp=$(wslpath -u "$win_temp")
                                cp "$install_crt" "$wsl_temp/$install_crt"
                                cert_win_path=$(wslpath -w "$wsl_temp/$install_crt" | tr -d '\r\n')
                                certutil.exe -user -addstore Root "$cert_win_path" || \
                                    cmd.exe /c "certutil -user -addstore Root \"$cert_win_path\"" || true
                                rm -f "$wsl_temp/$install_crt"
                                echo -e "${GREEN}✅ Windows import command executed.${NC}"
                                echo -e "${BLUE}ℹ️  Verify in Chrome: Settings > Security > Manage certificates > Trusted Root${NC}"
                            else
                                echo -e "${RED}❌ Could not determine Windows Temp path.${NC}"
                            fi
                        else
                            echo -e "${YELLOW}⚠️  cmd.exe not found — skipping Windows install (not running in WSL?).${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ Secret '$secret_name' not found.${NC}"
                fi
                read -p "$(t "press_enter")"
                ;;
            6)
                # Auto-Install Root CA (Selectable)
                echo -e "${BLUE}🪄 Auto-Installing Root CA...${NC}"
                
                # Select Issuer (Reuse logic or just pick file?)
                # Let's check for local .crt files first
                local crt_files
                crt_files=$(ls *.crt 2>/dev/null || true)
                
                local selected_crt
                if [ -n "$crt_files" ]; then
                     selected_crt=$(echo "$crt_files" | "$FZF_BIN" --height=20% --layout=reverse --border --prompt="Select Certificate File > " --header="Choose certificate to install" || true)
                else
                     echo -e "${YELLOW}No local .crt files found. Please use Option 5 to export one first.${NC}"
                     read -p "$(t "press_enter")"
                     continue
                fi
                
                if [ -z "$selected_crt" ]; then
                    continue
                fi

                echo -e "${BLUE}👉 Selected: $selected_crt${NC}"
                
                # 2. Install on WSL (Linux)
                echo -e "${BLUE}🐧 Installing on WSL/Linux...${NC}"
                if [ -d "/usr/local/share/ca-certificates" ]; then
                    sudo cp "$selected_crt" "/usr/local/share/ca-certificates/$selected_crt"
                    sudo update-ca-certificates
                    echo -e "${GREEN}✅ Installed in WSL system store.${NC}"
                else
                    echo -e "${YELLOW}⚠️  /usr/local/share/ca-certificates not found (non-Debian?)${NC}"
                fi
                
                # 3. Install on Windows (via interop)
                if command -v cmd.exe >/dev/null 2>&1; then
                    echo -e "${BLUE}🪟 Installing on Windows (Trusted Root)...${NC}"
                    echo -e "${YELLOW}⚠️  You may see a Windows prompt asking for permission.${NC}"
                    
                    # 1. Get Windows Temp path
                    local win_temp
                    win_temp=$(cmd.exe /c "echo %TEMP%" 2>/dev/null | tr -d '\r' || true)
                    
                    if [ -z "$win_temp" ]; then
                        echo -e "${RED}❌ Could not determine Windows Temp path.${NC}"
                    else
                        # 2. Convert to WSL path
                        local wsl_temp
                        wsl_temp=$(wslpath -u "$win_temp")
                        
                        # 3. Copy cert to Windows Temp
                        cp "$selected_crt" "$wsl_temp/$selected_crt"
                        
                        # 4. Get Windows path for the file (safer than manual concatenation)
                        local cert_win_path
                        cert_win_path=$(wslpath -w "$wsl_temp/$selected_crt" | tr -d '\r\n')
                        
                        echo -e "${BLUE}ℹ️  Debug: Checking file presence...${NC}"
                        ls -l "$wsl_temp/$selected_crt" || echo "❌ File not found in WSL path!"
                        
                        echo -e "${BLUE}ℹ️  Installing from: '${cert_win_path}'${NC}"
                        
                        # Use certutil.exe directly (bypassing cmd.exe quoting issues)
                        if command -v certutil.exe >/dev/null 2>&1; then
                             certutil.exe -user -addstore Root "$cert_win_path" || true
                        else
                             # Fallback to cmd.exe if certutil.exe not in path (unlikely)
                             cmd.exe /c "certutil -user -addstore Root \"$cert_win_path\"" || true
                        fi
                        
                        # 5. Cleanup
                        rm -f "$wsl_temp/$selected_crt"
                        
                        echo -e "${GREEN}✅ Windows import command executed.${NC}"
                    fi
                else
                    echo -e "${YELLOW}⚠️  Windows interop (cmd.exe) not found. Skipping Windows install.${NC}"
                fi
                
                read -p "$(t "press_enter")"
                ;;
            7)
                # Manual chain rebuild: trigger chain-repair job on-demand
                echo -e "${BLUE}🔗 Triggering chain-repair job...${NC}"
                local job_name="chain-repair-manual-$(date +%s)"
                run_kubectl "create job -n cert-manager $job_name --from=cronjob/chain-repair"
                echo -e "${YELLOW}Waiting for job to complete (max 2min)...${NC}"
                if run_kubectl "wait job/$job_name -n cert-manager --for=condition=complete --timeout=120s"; then
                    echo -e "${GREEN}✅ Chain rebuild complete. Logs:${NC}"
                    run_kubectl "logs -n cert-manager -l job-name=$job_name"
                else
                    echo -e "${RED}❌ Job did not complete in time. Check: kubectl logs -n cert-manager -l job-name=$job_name${NC}"
                fi
                run_kubectl "delete job $job_name -n default --ignore-not-found" >/dev/null 2>&1 || true
                read -p "$(t "press_enter")"
                ;;
            0)
                return
                ;;
        esac
    done
}

manage_snapshots() {
    while true; do
        echo -e "${BLUE}📸 Listing Available Snapshots...${NC}"
        
        # Get ALL VolumeSnapshots with metadata
        local snapshot_list
        snapshot_list=$(run_kubectl "get volumesnapshot -A -o json" | jq -r '.items[] | "\(.metadata.name)|\(.metadata.namespace)|\(.spec.source.persistentVolumeClaimName)|\(.status.creationTime // "N/A")|\(.status.restoreSize // "0" | tostring)|\(.status.readyToUse // false)|\(.status.boundVolumeSnapshotContentName // "")|\(.metadata.annotations["snapshot.longhorn.io/display-name"] // "")|\(.metadata.annotations["snapshot.longhorn.io/description"] // "")"')
        
        if [ -z "$snapshot_list" ]; then
            echo -e "${RED}No VolumeSnapshots found.${NC}"
            read -p "$(t "press_enter")"
            return
        fi
        
        echo -e "${BLUE}📊 Fetching snapshot sizes...${NC}"
        
        # Get ALL VolumeSnapshotContents and Longhorn Backups
        local all_snapshot_contents=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$MASTER_NODE" \
            "kubectl get volumesnapshotcontent -o json 2>/dev/null | jq -r '.items[] | \"\(.metadata.name)|\(.status.snapshotHandle // \"\")\"'")
        
        local all_backup_sizes=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$MASTER_NODE" \
            "kubectl get backups.longhorn.io -n longhorn-system -o json 2>/dev/null | jq -r '.items[] | \"\(.metadata.name)|\(.status.size // 0)\"'")
        
        # Format snapshots for display
        local formatted_snapshots=""
        while IFS='|' read -r snap_name snap_ns pvc_name creation_time capacity_size ready snapshot_content display_name description; do
            # Skip unready snapshots
            [ "$ready" != "true" ] && continue
            
            local capacity_display="$capacity_size"
            [ "$capacity_size" == "0" ] && capacity_display="N/A"
            
            # Get actual backup size
            local actual_size="N/A"
            if [ -n "$snapshot_content" ] && [ "$snapshot_content" != "null" ]; then
                local snapshot_handle=$(echo "$all_snapshot_contents" | grep "^${snapshot_content}|" | cut -d'|' -f2)
                
                if [ -n "$snapshot_handle" ] && [[ "$snapshot_handle" =~ backup-([a-f0-9]+) ]]; then
                    local backup_id="${BASH_REMATCH[1]}"
                    local backup_name="backup-${backup_id}"
                    local backup_size_bytes=$(echo "$all_backup_sizes" | grep "^${backup_name}|" | cut -d'|' -f2)
                    
                    if [ -n "$backup_size_bytes" ] && [ "$backup_size_bytes" != "0" ]; then
                        if [ "$backup_size_bytes" -lt 1048576 ]; then
                            actual_size=$(awk "BEGIN {printf \"%.0fKi\", $backup_size_bytes / 1024}")
                        elif [ "$backup_size_bytes" -lt 1073741824 ]; then
                            actual_size=$(awk "BEGIN {printf \"%.0fMi\", $backup_size_bytes / 1024 / 1024}")
                        else
                            actual_size=$(awk "BEGIN {printf \"%.2fGi\", $backup_size_bytes / 1024 / 1024 / 1024}")
                        fi
                    fi
                fi
            fi
            
            # Use display name if set, otherwise use actual name
            local name_display="${display_name:-$snap_name}"
            
            # Format timestamp
            local timestamp=$(echo "$creation_time" | cut -c1-19 | tr 'T' ' ')
            
            # Store for display and for data lookup separately
            formatted_snapshots+="${timestamp}|${pvc_name}|${snap_ns}|${actual_size}|${capacity_display}|${name_display}\n"
            # Store mapping for lookup
            echo "${timestamp}|${pvc_name}|${snap_ns}|${snap_ns}:${snap_name}" >> /tmp/snapshot_mapping_$$.txt
        done <<< "$snapshot_list"
        
        if [ -z "$formatted_snapshots" ]; then
            echo -e "${RED}No ready VolumeSnapshots found.${NC}"
            read -p "$(t "press_enter")"
            return
        fi
        
        # Sort and display with perfect alignment (no hidden columns)
        local sorted_snapshots=$(echo -e "$formatted_snapshots" | sort -r | column -t -s '|' -N "TIMESTAMP,PVC,NAMESPACE,ACTUAL,CAPACITY,DISPLAY_NAME")
        local header=$(echo "$sorted_snapshots" | head -1)
        local display_data=$(echo "$sorted_snapshots" | tail -n +2)
        
        local selected_snapshot
        selected_snapshot=$(echo "$display_data" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Select snapshot to manage (ESC to go back): " --header="$header") || true
        
        if [ -z "$selected_snapshot" ]; then
            rm -f /tmp/snapshot_mapping_$$.txt
            break  # Exit loop to go back to Backup Ops menu
        fi
        
        # Extract unique key (first 3 fields) and convert spaces to pipes for grep
        local timestamp=$(echo "$selected_snapshot" | awk '{print $1, $2}')
        local pvc=$(echo "$selected_snapshot" | awk '{print $3}')
        local namespace=$(echo "$selected_snapshot" | awk '{print $4}')
        local search_key="${timestamp}|${pvc}|${namespace}"
        local snapshot_info=$(grep "^${search_key}" /tmp/snapshot_mapping_$$.txt | head -1 | awk -F'|' '{print $NF}')
        rm -f /tmp/snapshot_mapping_$$.txt
        
        if [ -z "$snapshot_info" ]; then
            echo -e "${RED}❌ Error: Could not find snapshot info.${NC}"
            read -p "$(t "press_enter")"
            continue
        fi
        
        # Parse namespace:snapshot
        local snap_ns="${snapshot_info%%:*}"
        local snap_name="${snapshot_info##*:}"
        
        # Management submenu
        while true; do
            local mgmt_actions="1. View Details 📋
2. Set Display Name ✏️
3. Add/Edit Description 📝
4. Delete Snapshot 🗑️
0. Back"
            
            local mgmt_choice
            mgmt_choice=$(echo "$mgmt_actions" | "$FZF_BIN" --height=15% --layout=reverse --border --prompt="Manage $snap_name (ESC to go back) > " --header="Snapshot Management") || true
            
            case "${mgmt_choice%%.*}" in
                1)
                    # View Details
                    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo -e "${CYAN}📋 Snapshot Details: $snap_name${NC}"
                    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    run_kubectl "get volumesnapshot $snap_name -n $snap_ns -o yaml"
                    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    read -p "$(t "press_enter")"
                    ;;
                2)
                    # Set Display Name
                    echo -e "${CYAN}📝 Set Display Name for: $snap_name${NC}"
                    local current_display=$(run_kubectl "get volumesnapshot $snap_name -n $snap_ns -o jsonpath='{.metadata.annotations.snapshot\.longhorn\.io/display-name}'" 2>/dev/null || echo "")
                    
                    if [ -n "$current_display" ]; then
                        echo -e "${BLUE}Current display name: ${GREEN}$current_display${NC}"
                    else
                        echo -e "${YELLOW}No display name set (using real name: $snap_name)${NC}"
                    fi
                    
                    echo -e "${BLUE}Enter new display name (or 'clear' to remove):${NC}"
                    read -p "> " new_display_name
                    
                    if [ "$new_display_name" == "clear" ]; then
                        run_kubectl "annotate volumesnapshot $snap_name -n $snap_ns snapshot.longhorn.io/display-name-"
                        echo -e "${GREEN}✅ Display name cleared.${NC}"
                    elif [ -n "$new_display_name" ]; then
                        run_kubectl "annotate volumesnapshot $snap_name -n $snap_ns snapshot.longhorn.io/display-name=\"$new_display_name\" --overwrite"
                        echo -e "${GREEN}✅ Display name set to: $new_display_name${NC}"
                    fi
                    
                    read -p "$(t "press_enter")"
                    ;;
                3)
                    # Add/Edit Description
                    echo -e "${CYAN}📝 Add/Edit Description for: $snap_name${NC}"
                    local current_desc=$(run_kubectl "get volumesnapshot $snap_name -n $snap_ns -o jsonpath='{.metadata.annotations.snapshot\.longhorn\.io/description}'" 2>/dev/null || echo "")
                    
                    if [ -n "$current_desc" ]; then
                        echo -e "${BLUE}Current description:${NC}"
                        echo -e "${GREEN}$current_desc${NC}"
                        echo ""
                    fi
                    
                    echo -e "${BLUE}Enter new description (or 'clear' to remove):${NC}"
                    read -p "> " new_description
                    
                    if [ "$new_description" == "clear" ]; then
                        run_kubectl "annotate volumesnapshot $snap_name -n $snap_ns snapshot.longhorn.io/description-"
                        echo -e "${GREEN}✅ Description cleared.${NC}"
                    elif [ -n "$new_description" ]; then
                        run_kubectl "annotate volumesnapshot $snap_name -n $snap_ns snapshot.longhorn.io/description=\"$new_description\" --overwrite"
                        echo -e "${GREEN}✅ Description updated.${NC}"
                    fi
                    
                    read -p "$(t "press_enter")"
                    ;;
                4)
                    # Delete Snapshot
                    echo -e "${RED}⚠️  WARNING: Delete Snapshot${NC}"
                    echo -e "${BLUE}Snapshot: ${CYAN}$snap_name${NC}"
                    echo -e "${BLUE}Namespace: ${CYAN}$snap_ns${NC}"
                    echo -e "${YELLOW}This will permanently delete the snapshot and its underlying backup.${NC}"
                    echo ""
                    echo -e "${RED}Type the snapshot name to confirm deletion:${NC}"
                    read -p "> " confirm_name
                    
                    if [ "$confirm_name" == "$snap_name" ]; then
                        run_kubectl "delete volumesnapshot $snap_name -n $snap_ns"
                        echo -e "${GREEN}✅ Snapshot deleted.${NC}"
                        read -p "$(t "press_enter")"
                        break  # Exit submenu after deletion
                    else
                        echo -e "${YELLOW}❌ Deletion cancelled (name mismatch).${NC}"
                        read -p "$(t "press_enter")"
                    fi
                    ;;
                0)
                    break
                    ;;
            esac
        done
    done
}
backup_menu() {
schedule_snapshots() {
    while true; do
        local actions="1. Deploy Automated Snapshots 🚀
2. View Snapshot Schedule 📅
3. Configure Schedule/Retention ⚙️
4. Enable/Disable Auto-Snapshots 🔄
5. Test Snapshot Job Manually 🧪
0. Back"
        
        local choice
        choice=$(echo "$actions" | "$FZF_BIN" --height=15% --layout=reverse --border --prompt="Schedule Snapshots (ESC to go back) > " --header="Automated Snapshot Management") || true
        
        case "${choice%%.*}" in
            1)
                # Deploy Automated Snapshots
                echo -e "${CYAN}🚀 Deploying Automated Snapshot System${NC}"
                echo ""
                
                # 1. Deploy RBAC
                echo -e "${BLUE}Step 1/2: Creating ServiceAccount and RBAC...${NC}"
                if kubectl apply -f components/backup/snapshot-automation-rbac.yaml; then
                    echo -e "${GREEN}✅ RBAC configured${NC}"
                else
                    echo -e "${RED}❌ Failed to deploy RBAC${NC}"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                echo ""
                
                # 2. Deploy CronJob
                echo -e "${BLUE}Step 2/2: Creating Automated Snapshot CronJob...${NC}"
                if kubectl apply -f components/backup/snapshot-cronjob.yaml; then
                    echo -e "${GREEN}✅ CronJob created${NC}"
                else
                    echo -e "${RED}❌ Failed to deploy CronJob${NC}"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                echo ""
                echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${GREEN}✅ Automated Snapshots Deployed!${NC}"
                echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${BLUE}Schedule:${NC} Every 6 hours"
                echo -e "${BLUE}Retention:${NC} Last 7 snapshots"
                echo -e "${BLUE}Target PVC:${NC} postgres-pvc"
                echo -e "${BLUE}Namespace:${NC} postgres"
                
                read -p "$(t "press_enter")"
                ;;
            2)
                # View Schedule
                echo -e "${BLUE}📅 Snapshot Schedule Status${NC}"
                echo ""
                
                # Check if CronJob exists
                if run_kubectl "get cronjob postgres-auto-snapshot -n postgres" &>/dev/null; then
                    echo -e "${CYAN}=== CronJob Details ===${NC}"
                    run_kubectl "get cronjob postgres-auto-snapshot -n postgres"
                    echo ""
                    
                    echo -e "${CYAN}=== Recent Jobs ===${NC}"
                    run_kubectl "get jobs -n postgres -l app=postgres,component=backup-job --sort-by=.metadata.creationTimestamp | tail -5"
                    echo ""
                    
                    echo -e "${CYAN}=== Automated Snapshots ===${NC}"
                    run_kubectl "get volumesnapshot -n postgres -l snapshot-type=automated --sort-by=.metadata.creationTimestamp"
                else
                    echo -e "${YELLOW}⚠️  No automated snapshot CronJob found.${NC}"
                    echo -e "${BLUE}Use option 1 to deploy automated snapshots.${NC}"
                fi
                
                read -p "$(t "press_enter")"
                ;;
            3)
                # Configure Schedule/Retention
                echo -e "${CYAN}⚙️ Configure Snapshot Schedule${NC}"
                echo ""
                echo -e "${BLUE}Current configuration:${NC}"
                echo -e "  Schedule: Every 6 hours (0 */6 * * *)"
                echo -e "  Retention: 7 snapshots"
                echo -e "  PVC: postgres-pvc"
                echo ""
                
                echo -e "${YELLOW}To modify, edit: components/backup/snapshot-cronjob.yaml${NC}"
                echo ""
                echo -e "${BLUE}Common schedules:${NC}"
                echo -e "  Every hour:    ${GREEN}0 * * * *${NC}"
                echo -e "  Every 6 hours: ${GREEN}0 */6 * * *${NC}"
                echo -e "  Daily at 2 AM: ${GREEN}0 2 * * *${NC}"
                echo ""
                echo -e "${BLUE}To change retention, modify: ${GREEN}RETENTION_COUNT${NC} env var"
                
                read -p "$(t "press_enter")"
                ;;
            4)
                # Enable/Disable
                echo -e "${CYAN}🔄 Enable/Disable Automated Snapshots${NC}"
                echo ""
                
                if run_kubectl "get cronjob postgres-auto-snapshot -n postgres" &>/dev/null; then
                    # Check if suspended
                    local suspended=$(run_kubectl "get cronjob postgres-auto-snapshot -n postgres -o jsonpath='{.spec.suspend}'")
                    
                    if [ "$suspended" == "true" ]; then
                        echo -e "${YELLOW}Status: DISABLED${NC}"
                        echo -e "${BLUE}Enable automated snapshots?${NC}"
                        read -p "y/n: " confirm
                        
                        if [ "$confirm" == "y" ]; then
                            run_kubectl "patch cronjob postgres-auto-snapshot -n postgres -p '{\"spec\":{\"suspend\":false}}'"
                            echo -e "${GREEN}✅ Automated snapshots ENABLED${NC}"
                        fi
                    else
                        echo -e "${GREEN}Status: ENABLED${NC}"
                        echo -e "${BLUE}Disable automated snapshots?${NC}"
                        read -p "y/n: " confirm
                        
                        if [ "$confirm" == "y" ]; then
                            run_kubectl "patch cronjob postgres-auto-snapshot -n postgres -p '{\"spec\":{\"suspend\":true}}'"
                            echo -e "${YELLOW}✅ Automated snapshots DISABLED${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ CronJob not found. Deploy first (option 1).${NC}"
                fi
                
                read -p "$(t "press_enter")"
                ;;
            5)
                # Test manually
                echo -e "${CYAN}🧪 Testing Snapshot Job Manually${NC}"
                echo ""
                
                if ! run_kubectl "get cronjob postgres-auto-snapshot -n postgres" &>/dev/null; then
                    echo -e "${RED}❌ CronJob not found. Deploy first (option 1).${NC}"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                local test_job_name="snapshot-test-$(date +%s)"
                echo -e "${BLUE}Creating test job: $test_job_name${NC}"
                
                run_kubectl "create job --from=cronjob/postgres-auto-snapshot $test_job_name -n postgres"
                
                echo ""
                echo -e "${BLUE}Following job logs...${NC}"
                echo -e "${YELLOW}(Press Ctrl+C to stop watching)${NC}"
                echo ""
                
                sleep 2
                run_kubectl "logs -f job/$test_job_name -n postgres"
                
                echo ""
                echo -e "${BLUE}Check snapshot:${NC}"
                run_kubectl "get volumesnapshot -n postgres -l snapshot-type=automated --sort-by=.metadata.creationTimestamp | tail -1"
                
                read -p "$(t "press_enter")"
                ;;
            0)
                return
                ;;
        esac
    done
}
    while true; do
        local actions="1. Check Backup Status (Longhorn/Etcd) 📊
2. Trigger Manual Etcd Backup 💾
3. Trigger Manual Longhorn Snapshot 📸
4. View Backup Schedules (CronJobs) 🕒
5. Configure Backup Target (S3/Minio) ⚙️
6. Restore from Backup/Snapshot 🔄
7. Manage Backups/Snapshots 🗂️
8. Schedule Snapshots ⏰
9. Housekeeping (Cluster PVC Recovery) 🧹
10. Offsite Sync (Google Drive) ☁️
11. MinIO capacity — diagnose & prune backups (T-304) 📦
0. Back"
        
        local choice
        choice=$(echo "$actions" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Backup Ops (ESC to go back) > " --header="Backup & Disaster Recovery") || true
        
        if [ -z "$choice" ]; then
            break  # ESC pressed, go back
        fi
        
        case "${choice%%.*}" in
            10)
                echo -e "${BLUE}☁️  Running Google Drive Sync...${NC}"
                bash scripts/cloud_ops/sync_to_gdrive.sh
                read -p "$(t "press_enter")"
                ;;
            11)
                echo -e "${BLUE}📦 MinIO backup capacity (T-304)${NC}"
                ./scripts/backup/prune_minio_backup_capacity.sh --dry-run
                echo ""
                read -p "Apply prune now? (y/N): " CONFIRM
                if [[ "${CONFIRM:-}" =~ ^[yY]$ ]]; then
                    ./scripts/backup/prune_minio_backup_capacity.sh --apply
                fi
                read -p "$(t "press_enter")"
                ;;
            1)
                echo -e "${BLUE}📊 Checking Backup Status...${NC}"
                echo -e "${YELLOW}--- Etcd Backups ---${NC}"
                run_kubectl "get cronjob etcd-backup etcd-backup-prune -n kube-system"
                echo -e "${YELLOW}IaC:${NC} components/backup/etcd-backup-cronjob.yaml"
                echo ""
                echo -e "${YELLOW}--- Longhorn Backups ---${NC}"
                run_kubectl "get recurringjob -n longhorn-system"
                read -p "$(t "press_enter")"
                ;;
            2)
                echo -e "${BLUE}💾 Triggering Manual Etcd Backup...${NC}"
                run_kubectl "create job --from=cronjob/etcd-backup etcd-backup-manual-$(date +%s) -n kube-system"
                echo -e "${GREEN}✅ Backup job created.${NC}"
                echo -e "${YELLOW}ℹ️  Retention source of truth: components/backup/etcd-backup-cronjob.yaml${NC}"
                read -p "$(t "press_enter")"
                ;;
            3)
                echo -e "${BLUE}📸 Triggering Manual Longhorn Snapshot...${NC}"
                echo -e "${YELLOW}Select a volume to snapshot:${NC}"
                
                # Get volumes with PVC info
                local vol_info
                vol_info=$(run_kubectl "get volumes.longhorn.io -n longhorn-system -o json" | jq -r '.items[] | "\(.metadata.name)|\(.status.kubernetesStatus.pvcName // "no-pvc")|\(.status.kubernetesStatus.namespace // "")|\(.spec.size // "")"')
                
                if [ -z "$vol_info" ]; then
                    echo -e "${RED}No volumes found.${NC}"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                
                echo -e "${BLUE}📸 Creating CSI VolumeSnapshot...${NC}"
                
                # List PVCs across all namespaces
                local pvc_list=$(run_kubectl "get pvc -A -o json" | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"')
                
                if [ -z "$pvc_list" ]; then
                    echo -e "${RED}No PVCs found.${NC}"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                echo "Select a PVC to snapshot:"
                local selected_pvc=$(echo "$pvc_list" | "$FZF_BIN" --height=20% --layout=reverse --border --prompt="Select PVC: ") || true
                
                if [ -z "$selected_pvc" ]; then
                    continue
                fi
                
                local pvc_ns=$(echo "$selected_pvc" | cut -d/ -f1)
                local pvc_name=$(echo "$selected_pvc" | cut -d/ -f2)
                local snapshot_name="manual-$(date +%Y%m%d-%H%M%S)"
                
                echo -e "${BLUE}Creating VolumeSnapshot '$snapshot_name' for PVC '$pvc_name' in namespace '$pvc_ns'...${NC}"
                
                cat <<EOF | run_kubectl "apply -f -"
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $snapshot_name
  namespace: $pvc_ns
spec:
  volumeSnapshotClassName: longhorn-snapshot-vsc
  source:
    persistentVolumeClaimName: $pvc_name
EOF
                
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ VolumeSnapshot created successfully!${NC}"
                    echo -e "${BLUE}Checking snapshot status...${NC}"
                    run_kubectl "get volumesnapshot $snapshot_name -n $pvc_ns"
                else
                    echo -e "${RED}❌ Failed to create VolumeSnapshot.${NC}"
                fi
                read -p "$(t "press_enter")"
                ;;
            4)
                echo -e "${BLUE}🕒 Backup Schedules...${NC}"
                run_kubectl "get cronjobs -A"
                run_kubectl "get recurringjobs -n longhorn-system"
                echo -e "${YELLOW}ℹ️  ETCD backup/prune manifest: components/backup/etcd-backup-cronjob.yaml${NC}"
                read -p "$(t "press_enter")"
                ;;
            5)
                echo -e "${BLUE}⚙️  Configure Backup Target (S3/Minio)...${NC}"
                echo -e "${YELLOW}Current Target:${NC}"
                run_kubectl "get backuptargets.longhorn.io default -n longhorn-system"
                echo ""
                
                read -p "Enter S3 Endpoint URL (e.g., http://minio-service...:9000): " s3_endpoint
                read -p "Enter Bucket Name (e.g., k8s-backups): " s3_bucket
                read -p "Enter Region (default: us-east-1): " s3_region
                : "${s3_region:=us-east-1}"
                read -p "Enter Access Key: " s3_access
                read -s -p "Enter Secret Key: " s3_secret
                echo ""
                
                if [ -n "$s3_endpoint" ] && [ -n "$s3_bucket" ]; then
                    # 1. Update Secret
                    echo -e "${BLUE}Updating Secret...${NC}"
                    run_kubectl "create secret generic minio-secret -n longhorn-system --from-literal=AWS_ACCESS_KEY_ID=$s3_access --from-literal=AWS_SECRET_ACCESS_KEY=$s3_secret --from-literal=AWS_ENDPOINTS=$s3_endpoint --dry-run=client -o yaml | kubectl apply -f -"
                    
                    # 2. Update BackupTarget
                    echo -e "${BLUE}Updating BackupTarget...${NC}"
                    local target_url="s3://${s3_bucket}@${s3_region}/"
                    run_kubectl "patch backuptargets.longhorn.io default -n longhorn-system --type=merge -p '{\"spec\":{\"backupTargetURL\":\"$target_url\",\"credentialSecret\":\"minio-secret\"}}'"
                    
                    echo -e "${GREEN}✅ Backup Target Updated!${NC}"
                    echo -e "${YELLOW}ℹ️  Declarative manifest: components/backup/longhorn-backup-target.yaml${NC}"
                    echo -e "${YELLOW}   If you changed the bucket/region, update the manifest to keep IaC in sync.${NC}"
                else
                    echo -e "${RED}❌ Invalid input.${NC}"
                fi
                read -p "$(t "press_enter")"
                ;;
            6)
                echo -e "${BLUE}🔄 Restore from Backup/Snapshot...${NC}"
                echo -e "${YELLOW}Choose restore source:${NC}"
                local restore_type
                restore_type=$(echo -e "1. From Snapshot (local)\n2. From Backup (S3)" | "$FZF_BIN" --height=10% --layout=reverse --border --prompt="Restore from: ") || true
                
                if [[ "$restore_type" == "1."* ]]; then
                    # Restore from snapshot
                    echo -e "${BLUE}📸 Available Snapshots:${NC}"
                    
                    # List CSI VolumeSnapshots from all namespaces  
                    local snapshot_list
                    snapshot_list=$(run_kubectl "get volumesnapshot -A -o json" | jq -r '.items[] | "\(.metadata.name)|\(.metadata.namespace)|\(.spec.source.persistentVolumeClaimName)|\(.status.creationTime // "N/A")|\(.status.restoreSize // "0" | tostring)|\(.status.readyToUse // false)|\(.status.boundVolumeSnapshotContentName // "")"')
                    
                    if [ -z "$snapshot_list" ]; then
                        echo -e "${RED}No VolumeSnapshots found.${NC}"
                        echo -e "${YELLOW}Tip: Create snapshots with: kubectl create -f volumesnapshot.yaml${NC}"
                        read -p "$(t "press_enter")"
                        continue
                    fi
                    
                    # Get ALL VolumeSnapshotContents at once to extract backup IDs
                    echo -e "${BLUE}📊 Fetching snapshot sizes...${NC}"
                    local all_snapshot_contents=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$MASTER_NODE" \
                        "kubectl get volumesnapshotcontent -o json 2>/dev/null | jq -r '.items[] | \"\(.metadata.name)|\(.status.snapshotHandle // \"\")\"'")
                    
                    # Get ALL Longhorn Backups with actual sizes
                    local all_backup_sizes=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$MASTER_NODE" \
                        "kubectl get backups.longhorn.io -n longhorn-system -o json 2>/dev/null | jq -r '.items[] | \"\(.metadata.name)|\(.status.size // 0)\"'")
                    
                    # Format snapshots for display
                    local formatted_snapshots=""
                    while IFS='|' read -r snap_name snap_ns pvc_name creation_time capacity_size ready snapshot_content; do
                        # Capacity size already comes as string (e.g., "10Gi")
                        local capacity_display="$capacity_size"
                        [ "$capacity_size" == "0" ] && capacity_display="N/A"
                        
                        # Get actual backup size from Longhorn
                        local actual_size="N/A"
                        if [ -n "$snapshot_content" ] && [ "$snapshot_content" != "null" ]; then
                            # Get snapshotHandle (contains backup ID)
                            local snapshot_handle=$(echo "$all_snapshot_contents" | grep "^${snapshot_content}|" | cut -d'|' -f2)
                            
                            if [ -n "$snapshot_handle" ] && [[ "$snapshot_handle" =~ backup-([a-f0-9]+) ]]; then
                                local backup_id="${BASH_REMATCH[1]}"
                                local backup_name="backup-${backup_id}"
                                
                                # Look up actual size in Longhorn backups
                                local backup_size_bytes=$(echo "$all_backup_sizes" | grep "^${backup_name}|" | cut -d'|' -f2)
                                
                                if [ -n "$backup_size_bytes" ] && [ "$backup_size_bytes" != "0" ]; then
                                    # Convert bytes to human-readable
                                    if [ "$backup_size_bytes" -lt 1048576 ]; then
                                        # Less than 1MB, show in KB
                                        actual_size=$(awk "BEGIN {printf \"%.0fKi\", $backup_size_bytes / 1024}")
                                    elif [ "$backup_size_bytes" -lt 1073741824 ]; then
                                        # Less than 1GB, show in MB
                                        actual_size=$(awk "BEGIN {printf \"%.0fMi\", $backup_size_bytes / 1024 / 1024}")
                                    else
                                        # Show in GB
                                        actual_size=$(awk "BEGIN {printf \"%.2fGi\", $backup_size_bytes / 1024 / 1024 / 1024}")
                                    fi
                                fi
                            fi
                        fi
                        
                        # Format timestamp
                        local timestamp=$(echo "$creation_time" | cut -c1-19 | tr 'T' ' ')
                        
                        # Only show ready snapshots
                        if [ "$ready" == "true" ]; then
                            formatted_snapshots+="${creation_time}|${pvc_name}|${snap_ns}|${actual_size}|${capacity_display}|${snap_name}\n"
                        fi
                    done <<< "$snapshot_list"
                    
                    if [ -z "$formatted_snapshots" ]; then
                        echo -e "${RED}No ready VolumeSnapshots found.${NC}"
                        read -p "$(t "press_enter")"
                        continue
                    fi
                    
                    # Sort by timestamp DESC and format
                    local sorted_snapshots=$(echo -e "$formatted_snapshots" | sort -r | column -t -s '|' -N "TIMESTAMP,PVC,NAMESPACE,ACTUAL_SIZE,CAPACITY_SIZE,SNAPSHOT")
                    
                    # Extract header for fzf
                    local header=$(echo "$sorted_snapshots" | head -1)
                    local data=$(echo "$sorted_snapshots" | tail -n +2)
                    
                    local selected_snapshot
                    selected_snapshot=$(echo "$data" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Select snapshot: " --header="$header") || true
                    
                    if [ -n "$selected_snapshot" ]; then
                        # Extract snapshot name and PVC info from selection
                        local snap_name=$(echo "$selected_snapshot" | awk '{print $NF}')
                        local pvc_name=$(echo "$selected_snapshot" | awk '{print $2}')
                        local pvc_ns=$(echo "$selected_snapshot" | awk '{print $3}')
                        local snap_ns="$pvc_ns"  # Snapshot is in same namespace as PVC
                        
                        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                        echo -e "${CYAN}🔄 BLUE/GREEN RESTORE (Zero Downtime):${NC}"
                        echo -e "${CYAN}  1. Create new PVC from snapshot: ${GREEN}$snap_name${NC}"
                        echo -e "${CYAN}  2. Clone deployment with new PVC (green)${NC}"
                        echo -e "${CYAN}  3. Wait for green deployment to be ready${NC}"
                        echo -e "${CYAN}  4. Switch service to green deployment${NC}"
                        echo -e "${CYAN}  5. Remove old deployment and PVC (blue)${NC}"
                        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                        echo -e "${GREEN}✅ Application stays online during entire process!${NC}"
                        read -p "$(echo -e ${YELLOW}Continue with restore? [y/N]: ${NC})" confirm
                        
                        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
                            echo -e "${BLUE}Restore cancelled.${NC}"
                            read -p "$(t "press_enter")"
                            continue
                        fi
                        
                        
                        echo -e "${BLUE}🔍 Finding source PVC from snapshot...${NC}"
                        echo -e "${CYAN}  Snapshot: $snap_name (namespace: $snap_ns)${NC}"
                        
                        # Get source PVC from the snapshot (the PVC that was snapshotted)
                        # Execute kubectl + jq in single SSH command to avoid escaping issues
                        local source_pvc=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q "$MASTER_NODE" \
                            "kubectl get volumesnapshot $snap_name -n $snap_ns -o json | jq -r '.spec.source.persistentVolumeClaimName // empty'")
                        
                        if [ -z "$source_pvc" ]; then
                            echo -e "${RED}❌ Could not determine source PVC from snapshot.${NC}"
                            read -p "$(t "press_enter")"
                            continue
                        fi
                        
                        
                        echo -e "${BLUE}📦 Source PVC: ${CYAN}$source_pvc${NC}"
                        echo -e "${BLUE}🔍 Finding deployment using PVC '$source_pvc'...${NC}"
                        
                        # Find deployment using this PVC (only deployments supported for Blue/Green)
                        local deployments=$(run_kubectl "get deployments -n $pvc_ns -o json" | jq -r --arg pvc "$source_pvc" '.items[] | select(.spec.template.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) | .metadata.name')
                        
                        # FALLBACK: If not found, try alternate name (base <-> -green)
                        if [ -z "$deployments" ]; then
                            local alternate_pvc
                            if [[ "$source_pvc" =~ -green$ ]]; then
                                # Try base name (remove -green)
                                alternate_pvc="${source_pvc%-green}"
                            else
                                # Try -green variant
                                alternate_pvc="${source_pvc}-green"
                            fi
                            
                            echo -e "${YELLOW}⚠️  No deployment found, trying alternate PVC: $alternate_pvc${NC}"
                            deployments=$(run_kubectl "get deployments -n $pvc_ns -o json" | jq -r --arg pvc "$alternate_pvc" '.items[] | select(.spec.template.spec.volumes[]?.persistentVolumeClaim.claimName == $pvc) | .metadata.name')
                            
                            if [ -n "$deployments" ]; then
                                # Update source_pvc to the one actually in use
                                source_pvc="$alternate_pvc"
                                echo -e "${GREEN}✅ Found deployment using: $source_pvc${NC}"
                            fi
                        fi
                        
                        if [ -z "$deployments" ]; then
                            echo -e "${RED}❌ No deployment found using PVC '$source_pvc' or its alternate.${NC}"
                            echo -e "${YELLOW}Blue/Green restore only supports Deployments (not StatefulSets).${NC}"
                            read -p "$(t "press_enter")"
                            continue
                        fi
                        
                        local workload_name=$(echo "$deployments" | head -1)
                        echo -e "${BLUE}📦 Found deployment: ${CYAN}$workload_name${NC}"
                        
                        # Use source PVC as the current PVC (the one to be replaced)
                        pvc_name="$source_pvc"
                        
                        # Get deployment spec
                        local deployment_json=$(run_kubectl "get deployment $workload_name -n $pvc_ns -o json")
                        
                        # Fetch PVC and deployment specs
                        echo -e "${BLUE}📋 Fetching PVC specifications...${NC}"
                        local pvc_spec=$(run_kubectl "get pvc $pvc_name -n $pvc_ns -o json")
                        local storage_class=$(echo "$pvc_spec" | jq -r '.spec.storageClassName')
                        local access_modes=$(echo "$pvc_spec" | jq -r '.spec.accessModes[0] // "ReadWriteOnce"')
                        local storage_size=$(echo "$pvc_spec" | jq -r '.spec.resources.requests.storage')
                        
                        # BLUE/GREEN ALTERNATION LOGIC
                        # Detect current deployment color and create opposite
                        local current_deployment="$workload_name"
                        local is_current_green=false
                        
                        if [[ "$current_deployment" =~ -green$ ]]; then
                            # Current is GREEN → create BLUE (base name)
                            is_current_green=true
                            local base_name="${current_deployment%-green}"
                            local new_deployment="$base_name"
                            local new_pvc="${pvc_name%-green}"
                            local new_color="blue"
                            local old_color="green"
                        else
                            # Current is BLUE (base) → create GREEN
                            local base_name="$current_deployment"
                            local new_deployment="${current_deployment}-green"
                            local new_pvc="${pvc_name}-green"
                            local new_color="green"
                            local old_color="blue"
                        fi
                        
                        echo -e "${CYAN}🔄 Blue/Green Strategy:${NC}"
                        echo -e "${CYAN}   Current: ${YELLOW}$current_deployment${CYAN} ($old_color)${NC}"
                        echo -e "${CYAN}   Creating: ${GREEN}$new_deployment${CYAN} ($new_color)${NC}"
                        
                        # Step 1: Create new PVC from CSI VolumeSnapshot
                        echo -e "${BLUE}🟢 Step 1/5: Creating $new_color PVC from snapshot...${NC}"
                        
                        # Create PVC with dataSource pointing to VolumeSnapshot
                        cat <<EOF | run_kubectl "apply -f -"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $new_pvc
  namespace: $pvc_ns
  labels:
    restore-version: "$new_color"
    restored-from-snapshot: "$snap_name"
spec:
  accessModes:
    - $access_modes
  storageClassName: $storage_class
  resources:
    requests:
      storage: $storage_size
  dataSource:
    name: $snap_name
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

                        if [ $? -ne 0 ]; then
                            echo -e "${RED}❌ Failed to create PVC from snapshot.${NC}"
                            read -p "$(t "press_enter")"
                            continue
                        fi
                        
                        
                        # Wait for PVC to be Bound (manual polling - kubectl wait has race condition bug)
                        echo -e "${BLUE}⏳ Waiting for $new_color PVC to bind...${NC}"
                        local max_wait=300
                        local waited=0
                        local pvc_bound=false
                        
                        while [ $waited -lt $max_wait ]; do
                            local pvc_status=$(run_kubectl "get pvc $new_pvc -n $pvc_ns -o jsonpath='{.status.phase}' 2>/dev/null")
                            if [ "$pvc_status" == "Bound" ]; then
                                pvc_bound=true
                                break
                            fi
                            sleep 2
                            waited=$((waited + 2))
                        done
                        
                        if [ "$pvc_bound" != "true" ]; then
                            echo -e "${RED}❌ PVC failed to bind.${NC}"
                            run_kubectl "delete pvc $new_pvc -n $pvc_ns"
                            read -p "$(t "press_enter")"
                            continue
                        fi
                        
                        echo -e "${GREEN}✅ $new_color PVC bound and ready!${NC}"
                        
                        
                        # Step 2: Clone deployment with new PVC
                        echo -e "${BLUE}🟢 Step 2/5: Creating $new_color deployment...${NC}"
                        
                        # Clone deployment with modified PVC reference and labels
                        echo "$deployment_json" | jq --arg new_name "$new_deployment" --arg new_pvc "$new_pvc" --arg color "$new_color" --arg snapshot "$snap_name" '
                            .metadata.name = $new_name |
                            .metadata.labels."restore-version" = $color |
                            .metadata.labels."restored-from-snapshot" = $snapshot |
                            .spec.selector.matchLabels."restore-version" = $color |
                            .spec.template.metadata.labels."restore-version" = $color |
                            .spec.template.metadata.labels."restored-from-snapshot" = $snapshot |
                            .spec.template.spec.volumes[].persistentVolumeClaim.claimName = $new_pvc |
                            del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.generation, .status)
                        ' | run_kubectl "apply -f -"
                        
                        
                        # Step 3: Wait for new deployment
                        echo -e "${BLUE}🟢 Step 3/5: Waiting for $new_color deployment to be ready...${NC}"
                        run_kubectl "rollout status deployment/$new_deployment -n $pvc_ns --timeout=180s"
                        
                        if [ $? -ne 0 ]; then
                            echo -e "${RED}❌ $new_color deployment failed to become ready.${NC}"
                            echo -e "${YELLOW}Cleaning up $new_color resources...${NC}"
                            run_kubectl "delete deployment $new_deployment -n $pvc_ns"
                            run_kubectl "delete pvc $new_pvc -n $pvc_ns"
                            read -p "$(t "press_enter")"
                            continue
                        fi
                        
                        # CRITICAL: Wait extra time for pods to be ACTUALLY ready (not just deployment)
                        echo -e "${BLUE}⏳ Ensuring $new_color pods are fully ready...${NC}"
                        sleep 5
                        
                        # Verify new pods are running
                        local new_ready=$(run_kubectl "get deployment $new_deployment -n $pvc_ns -o jsonpath='{.status.readyReplicas}'")
                        if [ -z "$new_ready" ] || [ "$new_ready" -lt 1 ]; then
                            echo -e "${RED}❌ $new_color deployment has no ready pods!${NC}"
                            run_kubectl "delete deployment $new_deployment -n $pvc_ns"
                            run_kubectl "delete pvc $new_pvc -n $pvc_ns"
                            read -p "$(t "press_enter")"
                            continue
                        fi
                        
                        echo -e "${GREEN}✅ $new_color deployment ready with $new_ready pod(s)!${NC}"
                        
                        
                        # Step 4: Switch service to new deployment
                        echo -e "${BLUE}🔀 Step 4/5: Switching service to $new_color deployment...${NC}"
                        
                        # Find service pointing to current deployment (by app label, not restore-version)
                        local services=$(run_kubectl "get svc -n $pvc_ns -o json" | jq -r --arg app "$base_name" '.items[] | select(.spec.selector.app == $app) | .metadata.name')
                        
                        if [ -n "$services" ]; then
                            for svc in $services; do
                                echo -e "${BLUE}  Updating service: $svc${NC}"
                                run_kubectl "patch svc $svc -n $pvc_ns --type=merge -p '{\"spec\":{\"selector\":{\"restore-version\":\"$new_color\"}}}'"
                            done
                            echo -e "${GREEN}✅ Services switched to $new_color!${NC}"
                            sleep 5  # Grace period for connections to drain
                        fi
                                               
                        # Step 5: Clean up old deployment resources
                        echo -e "${BLUE}🗑️  Step 5/5: Removing old $old_color deployment and PVC...${NC}"
                        
                        # Keep old deployment running for 10s to allow connection draining
                        echo -e "${YELLOW}⏳ Waiting 10s for connection draining...${NC}"
                        sleep 10
                        
                        run_kubectl "delete deployment $current_deployment -n $pvc_ns --grace-period=30"
                        run_kubectl "delete pvc $pvc_name -n $pvc_ns"
                        
                        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                        echo -e "${GREEN}✅ Restore complete!${NC}"
                        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                        echo -e "${CYAN}📝 Active deployment: ${GREEN}$new_deployment${NC}"
                        echo -e "${CYAN}📝 Active PVC: ${GREEN}$new_pvc${NC}"
                        echo -e "${CYAN}📝 Restore labels: ${GREEN}restore-version=$new_color, restored-from-snapshot=$snap_name${NC}"
                        echo -e "${YELLOW}Monitor: kubectl get pods -n $pvc_ns -w${NC}"
                    fi
                    
                elif [[ "$restore_type" == "2."* ]]; then
                    # Restore from backup (S3)
                    echo -e "${BLUE}💾 Available Backups:${NC}"
                    local backup_list
                    backup_list=$(run_kubectl "get backups.longhorn.io -n longhorn-system -o json" | jq -r '.items[] | "\(.metadata.name)|\(.status.snapshotName)|\(.status.size // 0)|\(.status.snapshotCreatedAt // "N/A")"')
                    
                    if [ -z "$backup_list" ]; then
                        echo -e "${RED}No backups found.${NC}"
                        read -p "$(t "press_enter")"
                        continue
                    fi
                    
                    # Format backups
                    local formatted_backups=""
                    while IFS='|' read -r backup_name snapshot_name size creation_time; do
                        local size_hr=$(echo "$size" | awk '{ split( "B KB MB GB TB" , v ); s=1; while( $1>1024 ){ $1/=1024; s++ } printf "%.1f%s", $1, v[s] }')
                        formatted_backups+="$backup_name (from: $snapshot_name) [$size_hr] - $creation_time\n"
                    done <<< "$backup_list"
                    
                    local selected_backup
                    selected_backup=$(echo -e "$formatted_backups" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Select backup: ") || true
                    
                    if [ -n "$selected_backup" ]; then
                        local backup_name=$(echo "$selected_backup" | awk '{print $1}')
                        echo -e "${YELLOW}⚠️  Backup restore via CLI is complex. Recommended: Use Longhorn UI (Backup tab → Restore).${NC}"
                        echo -e "${BLUE}Selected backup: $backup_name${NC}"
                    fi
                fi
                
                read -p "$(t "press_enter")"
                ;;
            7)
                manage_snapshots
                ;;
            8)
                schedule_snapshots
                ;;
            9)
                clear
                # Execute in subshell to isolate environment and exit codes
                (bash scripts/volume_manager/housekeeping.sh < /dev/tty) || true
                
                # Restore terminal state
                stty sane
                
                echo ""
                read -p "Press Enter to return to menu..."
                ;;
            0)
                return
                ;;
        esac
    done
}

access_menu() {
  while true; do
    local actions="$(t "access_start_tunnel")
$(t "access_manage_tunnels")
3. Bridge Status & Cleanup (netsh) 🌉
4. Ingress & DNS Helper 🌐
$(t "prefs_back")"

    local selected_action
    selected_action=$(echo "$actions" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Tunnel Manager > ") || true

    if [ -z "$selected_action" ]; then
      return
    fi

    case "${selected_action%%.*}" in
      1) start_tunnel ;;
      2) 
        manage_tunnels
        # Only exit to main menu if manage_tunnels explicitly returns 0
        local ret=$?
        if [ $ret -eq 0 ]; then
            return 0
        fi
        # Any other return code (like 1) means continue in access_menu
        ;;
      3) manage_bridges ;;
      4) ingress_menu ;;
      0) return ;;
    esac
  done
}
# --- SERVICE CONFIGURATION MENUS ---

# Source automation library scripts
source "$SCRIPT_DIR/lib/minio_init.sh"
source "$SCRIPT_DIR/lib/nexus_init.sh"

# View stored credentials
view_credentials_menu() {
  while true; do
    # Get list of credentials (name - description)
    local cred_list
    cred_list=$(credstore_list_names)
    
    if [ -z "$cred_list" ]; then
      clear
      echo -e "${YELLOW}No credentials stored yet.${NC}"
      echo ""
      read -p "Press Enter to return..."
      return
    fi
    
    # Select credential with fzf (search enabled by default)
    local selected
    selected=$(echo -e "0. Back\n$cred_list" | "$FZF_BIN" \
      --height=60% \
      --layout=reverse \
      --border \
      --prompt="Search Credentials (ESC to go back) > " \
      --header="Type to search by name or description" \
      --preview="echo 'Select to view actions'" \
      --preview-window=down:2) || true
    
    if [ -z "$selected" ] || [ "$selected" = "0. Back" ]; then
      return
    fi
    
    # Extract credential name (before " - ")
    local cred_name="${selected%% - *}"
    
    # Show actions for selected credential
    while true; do
      clear
      echo -e "${BLUE}=== Credential: $cred_name ===${NC}"
      echo ""
      
      local actions="1. Show Secret Values 👁️
2. Edit 📝
3. Copy Username 📋
4. Copy Password 📋
5. Delete 🗑️
0. Back"
      
      local action
      action=$(echo "$actions" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Action > ") || true
      
      if [ -z "$action" ] || [[ "$action" == "0. Back" ]]; then
        break
      fi
      
      case "${action%%.*}" in
        1)
          # Show secret values
          clear
          echo -e "${BLUE}=== Credential Details ===${NC}"
          echo ""
          
          local cred_json
          cred_json=$(credstore_get_credential "$cred_name" 2>/dev/null || echo "{}")
          
          if [ "$cred_json" = "{}" ]; then
            echo -e "${RED}Error: Credential not found${NC}"
            read -p "Press Enter..."
            continue
          fi
          
          local username=$(echo "$cred_json" | jq -r '.username')
          local password=$(echo "$cred_json" | jq -r '.password')
          local description=$(echo "$cred_json" | jq -r '.description')
          
          echo -e "${GREEN}Name:${NC} $cred_name"
          echo -e "${GREEN}Description:${NC} $description"
          echo -e "${GREEN}Username:${NC} $username"
          echo -e "${GREEN}Password:${NC} ${password:0:10}********** ${GRAY}[hidden]${NC}"
          echo ""
          echo -e "${YELLOW}💡 Use 'Copy Username' or 'Copy Password' to get the full values${NC}"
          echo ""
          read -p "Press Enter..."
          ;;
        2)
          # Edit credential
          clear
          echo -e "${BLUE}=== Edit Credential: $cred_name ===${NC}"
          echo ""
          
          local edit_menu="1. Edit Username
2. Edit Password
3. Edit Description
0. Cancel"
          
          local edit_action
          edit_action=$(echo "$edit_menu" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Edit > ") || true
          
          if [ -z "$edit_action" ] || [[ "$edit_action" == "0. Cancel" ]]; then
            continue
          fi
          
          case "${edit_action%%.*}" in
            1)
              echo -e "${BLUE}Enter new username:${NC}"
              read -r new_username
              credstore_update "$cred_name" "username" "$new_username"
              echo -e "${GREEN}✓ Username updated${NC}"
              read -p "Press Enter..."
              ;;
            2)
              echo -e "${BLUE}Enter new password:${NC}"
              read -rs new_password
              echo ""
              credstore_update "$cred_name" "password" "$new_password"
              echo -e "${GREEN}✓ Password updated${NC}"
              read -p "Press Enter..."
              ;;
            3)
              echo -e "${BLUE}Enter new description:${NC}"
              read -r new_description
              credstore_update "$cred_name" "description" "$new_description"
              echo -e "${GREEN}✓ Description updated${NC}"
              read -p "Press Enter..."
              ;;
          esac
          ;;
        3)
          # Copy username
          local cred_json
          cred_json=$(credstore_get_credential "$cred_name" 2>/dev/null || echo "{}")
          local username=$(echo "$cred_json" | jq -r '.username')
          
          if command -v clip.exe >/dev/null 2>&1; then
            echo -n "$username" | clip.exe
            echo -e "${GREEN}✓ Username copied to clipboard${NC}"
          else
            echo -e "${YELLOW}Username: $username${NC}"
          fi
          read -p "Press Enter..."
          ;;
        4)
          # Copy password
          local cred_json
          cred_json=$(credstore_get_credential "$cred_name" 2>/dev/null || echo "{}")
          local password=$(echo "$cred_json" | jq -r '.password')
          
          if command -v clip.exe >/dev/null 2>&1; then
            echo -n "$password" | clip.exe
            echo -e "${GREEN}✓ Password copied to clipboard${NC}"
          else
            echo -e "${YELLOW}Password: ${password:0:10}**********${NC}"
          fi
          read -p "Press Enter..."
          ;;
        5)
          # Delete credential
          echo -e "${RED}Are you sure you want to delete '$cred_name' ? (yes/no)${NC}"
          read -r confirm
          if [[ "$confirm" == "yes" ]]; then
            credstore_delete_credential "$cred_name"
            echo -e "${GREEN}✓ Credential deleted${NC}"
            read -p "Press Enter..."
            break  # Return to credential list
          else
            echo -e "${YELLOW}Cancelled${NC}"
            read -p "Press Enter..."
          fi
          ;;
      esac
    done
  done
}

# Service configuration menu
service_config_menu() {
  while true; do
    local actions="$(t "svc_minio_init")
$(t "svc_nexus_init")
$(t "svc_nexus_reset")
$(t "svc_auto_init")
$(t "prefs_back")"
    
    local selected
    selected=$(echo "$actions" | "$FZF_BIN" --height=50% --layout=reverse --border --prompt="Service Configuration > " --header="Automated Service Setup") || true
    
    if [ -z "$selected" ] || [[ "$selected" == "$(t "prefs_back")" ]]; then
      return
    fi
    
    case "${selected%%.*}" in
      1)
        clear
        echo -e "${BLUE}=== Minio Initialization ===${NC}"
        echo ""
        
        # Check if Minio is running
        if ! run_kubectl "get pods -n minio -l app=minio" | grep -q "Running"; then
          echo -e "${RED}Error: Minio pod is not running${NC}"
          echo "Please deploy Minio first via Component Management menu"
          read -p "$(t "press_enter")"
          continue
        fi
        
        minio_initialize
        read -p "$(t "press_enter")"
        ;;
      2)
        clear
        echo -e "${BLUE}=== Nexus Initialization ===${NC}"
        echo ""
        
        # Check if Nexus is running
        if ! run_kubectl "get pods -n nexus -l app=nexus" | grep -q "Running"; then
          echo -e "${RED}Error: Nexus pod is not running${NC}"
          echo "Please deploy Nexus first via Component Management menu"
          read -p "$(t "press_enter")"
          continue
        fi
        
        # Check tunnel
        if ! lsof -i :8081 >/dev/null 2>&1; then
          echo -e "${YELLOW}No tunnel to Nexus detected${NC}"
          echo "Opening tunnel to Nexus on port 8081..."
          
          # Start tunnel in background
          local nexus_nodeport
          nexus_nodeport=$(run_kubectl "get svc -n nexus nexus-service -o jsonpath='{.spec.ports[0].nodePort}'" | tr -d '\r')
          
          ssh -f -N -L 8081:127.0.0.1:$nexus_nodeport \
            -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$MASTER_NODE"
          
          # Store tunnel metadata
          echo "nexus-service|nexus|nexus-service|http" > "$TUNNEL_DIR/8081.meta"
          
          sleep 2
          echo -e "${GREEN}✓ Tunnel established${NC}"
          echo ""
        fi
        
        nexus_initialize
        read -p "$(t "press_enter")"
        ;;
      3)
        clear
        echo -e "${RED}=== Reset Nexus ===${NC}"
        echo ""
        echo -e "${YELLOW}⚠️  WARNING: This will DELETE all Nexus data!${NC}"
        echo "   - All repositories will be removed"
        echo "   - All blob stores will be removed"
        echo "   - All credentials will be reset"
        echo ""
        read -p "Are you sure? Type 'yes' to confirm: " confirm
        
        if [ "$confirm" != "yes" ]; then
          echo "Reset cancelled."
          read -p "$(t "press_enter")"
          continue
        fi
        
        nexus_reset
        read -p "$(t "press_enter")"
        ;;
      4)
        clear
        echo -e "${BLUE}=== Auto-Initialize All Services ===${NC}"
        echo ""
        
        # Step 1: Minio
        echo -e "${YELLOW}[1/2] Initializing Minio...${NC}"
        echo ""
        minio_initialize || {
          echo -e "${RED}Minio initialization failed${NC}"
          read -p "$(t "press_enter")"
          continue
        }
        
        echo ""
        echo -e "${YELLOW}[2/2] Initializing Nexus...${NC}"
        echo ""
        
        # Ensure tunnel for Nexus
        if ! lsof -i :8081 >/dev/null 2>&1; then
          local nexus_nodeport
          nexus_nodeport=$(run_kubectl "get svc -n nexus nexus-service -o jsonpath='{.spec.ports[0].nodePort}'" | tr -d '\r')
          ssh -f -N -L 8081:127.0.0.1:$nexus_nodeport \
            -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$MASTER_NODE"
          sleep 2
        fi
        
        nexus_initialize || {
          echo -e "${RED}Nexus initialization failed${NC}"
          read -p "$(t "press_enter")"
          continue
        }
        
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}✓ All services initialized successfully!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        read -p "$(t "press_enter")"
        ;;
    esac
  done
}

# --- PREFERENCES MENU ---

# Get port status for display (multiline format with URLs)

get_port_status() {
    local tunnel_data
    tunnel_data=$(discover_active_tunnels)
    
    if [ -z "$tunnel_data" ]; then
        echo "$(t "port_status_none")"
    else
        # Build multiline status with protocol and URLs
        local count=0
        local status_lines=""
        
        while IFS='|' read -r pid svc_info namespace local_port remote_port bind_ip_raw; do
            # Extract service name and protocol
            local svc_name="$svc_info"
            local protocol="tcp"
            
            # Check if protocol info is embedded (format: "service [protocol]")
            if [[ "$svc_info" == *"["* ]]; then
                protocol="${svc_info##*[}"
                protocol="${protocol%%]*}"
                svc_name="${svc_info%% [*}"
            fi
            
            # Get clean service name
            if [[ "$svc_name" == *"/"* ]]; then
                svc_name="${svc_name##*/}"
            fi
            
            # Determine display host
            local display_host="localhost"
            if [ -n "$bind_ip_raw" ] && [ "$bind_ip_raw" != "127.0.0.1" ] && [ "$bind_ip_raw" != "localhost" ]; then
                display_host="$bind_ip_raw"
            fi
            
            # Build URL if http/https
            local url_info=""
            if [[ "$protocol" == "http" ]] || [[ "$protocol" == "https" ]]; then
                url_info=" → ${protocol}://${display_host}:${local_port}"
            else
                if [ "$display_host" != "localhost" ]; then
                     url_info=" → ${display_host}:${local_port} [$protocol]"
                else
                     url_info=" [$protocol]"
                fi
            fi
            
            # Add to status lines
            if [ $count -eq 0 ]; then
                status_lines="  • $local_port ($svc_name)$url_info"
            else
                status_lines+=$'\n'"  • $local_port ($svc_name)$url_info"
            fi
            ((count++))
        done <<< "$tunnel_data"
        
        echo -e "$(t "port_status_active") ($count):\n$status_lines"
    fi
}

# Auto-forward ports on startup
auto_forward_ports() {
    local auto_ports
    auto_ports=$(prefs_get_auto_ports)
    
    # Check if there are any ports to forward
    local port_count
    port_count=$(echo "$auto_ports" | jq 'length')
    
    if [ "$port_count" -eq 0 ]; then
        return 0
    fi
    
    echo -e "${BLUE}$(t "auto_ports_starting")${NC}"
    
    local i=0
    while [ $i -lt $port_count ]; do
        local namespace=$(echo "$auto_ports" | jq -r ".[$i].namespace")
        local service=$(echo "$auto_ports" | jq -r ".[$i].service")
        local desired_port=$(echo "$auto_ports" | jq -r ".[$i].port")
        
        # Check if tunnel already exists for this port
        if lsof -i :$desired_port >/dev/null 2>&1; then
            echo -e "  ${GRAY}Port $desired_port already in use, skipping${NC}"
            ((i++))
            continue
        fi
        
        # Get NodePort for the service
        local nodeport
        nodeport=$(run_kubectl "get svc -n $namespace $service -o jsonpath='{.spec.ports[0].nodePort}'" 2>/dev/null | tr -d '\r')
        
        if [ -z "$nodeport" ]; then
            echo -e "  ${RED}$(t "auto_ports_failed"): $service (service not found)${NC}"
            ((i++))
            continue
        fi
        
        # Find available local port
        local local_port=$(find_available_port "$desired_port")
        
        # Start tunnel in background
        ssh -f -N -L "0.0.0.0:$local_port:127.0.0.1:$nodeport" \
            -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ExitOnForwardFailure=yes \
            "$MASTER_NODE" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            # Save metadata
            echo "$namespace/$service|$namespace|$service|tcp" > "$TUNNEL_DIR/$local_port.meta"
            echo -e "  ${GREEN}$(t "auto_ports_success"): $service on port $local_port${NC}"
        else
            echo -e "  ${RED}$(t "auto_ports_failed"): $service${NC}"
        fi
        
        ((i++))
    done
    
    sleep 1
}

# Configure auto port forwarding
configure_auto_ports_menu() {
    while true; do
        clear
        echo -e "${BLUE}=== $(t "auto_ports_title") ===${NC}"
        echo ""
        
        # List current ports
        local auto_ports
        auto_ports=$(prefs_get_auto_ports)
        local port_count
        port_count=$(echo "$auto_ports" | jq 'length')
        
        if [ "$port_count" -gt 0 ]; then
            echo -e "${GREEN}$(t "auto_ports_current"):${NC}"
            local i=0
            while [ $i -lt $port_count ]; do
                local namespace=$(echo "$auto_ports" | jq -r ".[$i].namespace")
                local service=$(echo "$auto_ports" | jq -r ".[$i].service")
                local port=$(echo "$auto_ports" | jq -r ".[$i].port")
                echo "  - $namespace/$service:$port"
                ((i++))
            done
        else
            echo -e "${YELLOW}$(t "auto_ports_none")${NC}"
        fi
        
        echo ""
        local actions="$(t "auto_ports_add")
$(t "auto_ports_remove")
$(t "prefs_back")"
        
        local selected
        selected=$(echo "$actions" | "$FZF_BIN" --height=20% --layout=reverse --border --prompt="Auto Ports > ") || true
        
        if [ -z "$selected" ] || [[ "$selected" == "$(t "prefs_back")" ]]; then
            return
        fi
        
        case "${selected%%.*}" in
            1)
                # Add port
                echo ""
                echo -e "${BLUE}Enter namespace:${NC}"
                read -r namespace
                echo -e "${BLUE}Enter service name:${NC}"
                read -r service
                echo -e "${BLUE}Enter desired local port:${NC}"
                read -r port
                
                if [ -n "$namespace" ] && [ -n "$service" ] && [ -n "$port" ]; then
                    prefs_add_auto_port "$namespace" "$service" "$port"
                    echo -e "${GREEN}$(t "auto_ports_added")${NC}"
                    sleep 1
                fi
                ;;
            2)
                # Remove port
                if [ "$port_count" -eq 0 ]; then
                    echo -e "${YELLOW}$(t "auto_ports_none")${NC}"
                    read -p "$(t "press_enter")"
                    continue
                fi
                
                # Build menu of configured ports
                local port_menu=""
                local i=0
                while [ $i -lt $port_count ]; do
                    local namespace=$(echo "$auto_ports" | jq -r ".[$i].namespace")
                    local service=$(echo "$auto_ports" | jq -r ".[$i].service")
                    local port=$(echo "$auto_ports" | jq -r ".[$i].port")
                    port_menu+="$namespace/$service:$port"$'\n'
                    ((i++))
                done
                
                local to_remove
                to_remove=$(echo "$port_menu" | "$FZF_BIN" --height=20% --layout=reverse --border --prompt="Remove > ") || true
                
                if [ -n "$to_remove" ]; then
                    local namespace=$(echo "$to_remove" | cut -d'/' -f1)
                    local service_port=$(echo "$to_remove" | cut -d'/' -f2)
                    local service=$(echo "$service_port" | cut -d':' -f1)
                    local port=$(echo "$service_port" | cut -d':' -f2)
                    
                    prefs_remove_auto_port "$namespace" "$service" "$port"
                    echo -e "${GREEN}$(t "auto_ports_removed")${NC}"
                    sleep 1
                fi
                ;;
        esac
    done
}

# Preferences menu
preferences_menu() {
    while true; do
        clear
        echo -e "${BLUE}=== $(t "prefs_menu_title") ===${NC}"
        echo ""
        echo -e "${GRAY}Current Language: $(prefs_get_language)${NC}"
        echo ""
        
        local actions="$(t "prefs_change_lang")
$(t "prefs_reorder_menu")
$(t "prefs_auto_ports")
$(t "prefs_back")"
        
        local selected
        selected=$(echo "$actions" | "$FZF_BIN" --height=30% --layout=reverse --border --prompt="Preferences > ") || true
        
        if [ -z "$selected" ] || [[ "$selected" == "$(t "prefs_back")" ]]; then
            return
        fi
        
        case "${selected%%.*}" in
            1)
                # Change language
                clear
                echo -e "${BLUE}=== $(t "lang_select_title") ===${NC}"
                echo ""
                
                local lang_menu="$(t "lang_english")
$(t "lang_portuguese")
$(t "prefs_back")"
                
                local lang_selected
                lang_selected=$(echo "$lang_menu" | "$FZF_BIN" --height=20% --layout=reverse --border --prompt="Language > ") || true
                
                if [ -z "$lang_selected" ] || [[ "$lang_selected" == "$(t "prefs_back")" ]]; then
                    continue
                fi
                
                case "${lang_selected%%.*}" in
                    1)
                        prefs_set_language "en"
                        export I18N_LANG="en"
                        echo -e "${GREEN}$(t "lang_changed") English${NC}"
                        ;;
                    2)
                        prefs_set_language "pt_BR"
                        export I18N_LANG="pt_BR"
                        echo -e "${GREEN}$(t "lang_changed") Português (Brasil)${NC}"
                        ;;
                esac
                read -p "$(t "press_enter")"
                ;;
            2)
                # Reorder menu items
                while true; do
                    clear
                    echo -e "${BLUE}=== $(t "prefs_reorder_menu") ===${NC}"
                    echo ""
                    
                    # Get current order
                    local current_order
                    current_order=$(prefs_get_menu_order)
                    
                    # Convert to bash array
                    local menu_keys=()
                    while IFS= read -r key; do
                        menu_keys+=("$key")
                    done < <(echo "$current_order" | jq -r '.[]')
                    
                    echo -e "${GREEN}Current menu order:${NC}"
                    local i=1
                    for key in "${menu_keys[@]}"; do
                        local name=""
                        case "$key" in
                            "k9s") name="Advanced Dashboard (k9s)" ;;
                            "port_forward") name="Access & Port Forwarding" ;;
                            "service_config") name="Service Configuration" ;;
                            "credentials") name="View Credentials" ;;
                            "components") name="Component Management" ;;
                            "dashboard") name="Open Kubernetes Dashboard" ;;
                            "namespace") name="Change Namespace" ;;
                            "pod") name="Select Pod" ;;
                            "all_pods") name="Show All Pods" ;;
                            "nodes") name="Node Status" ;;
                            "update") name="Safe Node Update" ;;
                            "maintenance") name="Cluster Maintenance" ;;
                            "preferences") name="Preferences" ;;
                            "exit") name="Exit" ;;
                        esac
                        echo "  $i. $name"
                        ((i++))
                    done
                    
                    echo ""
                    echo -e "${YELLOW}Actions:${NC}"
                    echo "1-${#menu_keys[@]}. Move item (enter number)"
                    echo "s. Save and Exit"
                    echo "r. Reset to default"
                    echo "q. Cancel (don't save)"
                    echo ""
                    read -p "Choose action: " action
                    
                    case "$action" in
                        s)
                            # Save
                            local json_array="["
                            for key in "${menu_keys[@]}"; do
                                json_array+="\"$key\","
                            done
                            json_array="${json_array%,}]"
                            
                            prefs_set_menu_order "$json_array"
                            echo -e "${GREEN}✓ Menu order saved!${NC}"
                            echo -e "${YELLOW}Restart TUI to see changes${NC}"
                            read -p "$(t "press_enter")"
                            break
                            ;;
                        r)
                            # Reset
                            prefs_set_menu_order "$DEFAULT_MENU_ORDER"
                            echo -e "${GREEN}✓ Reset to default!${NC}"
                            read -p "$(t "press_enter")"
                            break
                            ;;
                        q)
                            # Cancel
                            echo -e "${GRAY}Cancelled${NC}"
                            read -p "$(t "press_enter")"
                            break
                            ;;
                        *)
                            # Try to move item
                            if [[ "$action" =~ ^[0-9]+$ ]] && [ "$action" -ge 1 ] && [ "$action" -le "${#menu_keys[@]}" ]; then
                                # Valid item selected
                                local from_pos=$action
                                echo ""
                                echo -e "${BLUE}Move '${menu_keys[$((from_pos-1))]}' to position:${NC}"
                                read -p "New position (1-${#menu_keys[@]}): " to_pos
                                
                                if [[ "$to_pos" =~ ^[0-9]+$ ]] && [ "$to_pos" -ge 1 ] && [ "$to_pos" -le "${#menu_keys[@]}" ]; then
                                    local from_idx=$((from_pos - 1))
                                    local to_idx=$((to_pos - 1))
                                    
                                    if [ $from_idx -ne $to_idx ]; then
                                        # Simple move: extract item, build new array
                                        local item="${menu_keys[$from_idx]}"
                                        local new_arr=()
                                        
                                        # Build new array in one pass
                                        for ((k=0; k<=${#menu_keys[@]}; k++)); do
                                            # Insert item at target position
                                            if [ $k -eq $to_idx ]; then
                                                new_arr+=("$item")
                                            fi
                                            
                                            # Copy other items (skip the original position)
                                            if [ $k -lt ${#menu_keys[@]} ] && [ $k -ne $from_idx ]; then
                                                new_arr+=("${menu_keys[$k]}")
                                            fi
                                        done

                                        
                                        menu_keys=("${new_arr[@]}")
                                        echo -e "${GREEN}✓ Moved!${NC}"
                                    fi
                                else
                                    echo -e "${RED}Invalid position${NC}"
                                fi
                                sleep 1
                            else
                                echo -e "${RED}Invalid choice${NC}"
                                sleep 1
                            fi
                            ;;
                    esac
                done
                ;;
            3)
                # Configure auto port forwarding
                configure_auto_ports_menu
                
                echo ""
                echo -e "${GRAY}(Use 'sudo nano /etc/hosts' to edit)${NC}"
                echo ""
                read -p "$(t "press_enter")"
                ;;
            0)
                return
                ;;
            *)
                echo "$(t "invalid_option")"
                sleep 1
                ;;
        esac
    done
}

# --- SECURITY AUDIT ---

security_audit_menu() {
  while true; do
    local log_file="/var/log/k8s_ops.log"
    # Fallback if no sudo access
    if [ ! -f "$log_file" ] && [ -f "$HOME/.k8s_ops.log" ]; then
      log_file="$HOME/.k8s_ops.log"
    fi

    echo -e "${BLUE}🛡️  Security Audit Menu${NC}"
    echo ""
    echo "1. View Audit Log (Last 50 entries) 📜"
    echo "2. View Audit Log (Full / Interactive) 🔍"
    echo "3. Scan Known Hosts (Fixes MITM Risk) 🔑"
    echo "0. Back"
    echo ""
    read -p "Choose option: " choice

    case "$choice" in
      1)
        clear
        echo -e "${YELLOW}Last 50 Audit Entries:${NC}"
        echo "------------------------------------------------"
        if [ -f "$log_file" ]; then
            tail -n 50 "$log_file"
        else
            echo "No audit log found at $log_file"
        fi
        echo ""
        read -p "Press Enter..."
        ;;
      2)
        if [ -f "$log_file" ]; then
            less +G "$log_file"
        else
            echo "No audit log found."
            sleep 2
        fi
        ;;
      3)
        echo -e "${YELLOW}Running SSH Host Key Scanner...${NC}"
        source scripts/security/scan_known_hosts.sh
        read -p "Press Enter..."
        ;;
      0)
        return
        ;;
      *)
        echo "Invalid option"
        sleep 1
        ;;
    esac
  done
}

# --- TUNNEL MANAGEMENT ---

node_maintenance_menu() {
  while true; do
    sync
    CHOICE=$(whiptail --title "Node Maintenance & Hardening" --menu "Select Maintenance Task:" 20 80 8 \
      "1" "Disk Optimizer (Resize/Prune)" \
      "2" "Node Fixer (Auto-Repair)" \
      "3" "System Cleaner (Cache/Logs)" \
      "4" "Node Hardening (Safety/Watchdog)" \
      "0" "Back to Main Menu" 3>&1 1>&2 2>&3)
    
    if [ $? != 0 ]; then return; fi

    case "$CHOICE" in
      1)
        source scripts/disk_manager/tui_disk.sh
        node_disk_optimizer_menu
        ;;
      2)
        source scripts/node_fixer/tui_node_fixer.sh
        node_fixer_menu
        ;;
      3)
        source scripts/system_cleaner/tui_system_cleaner.sh
        system_cleaner_menu
        ;;
      4)
        show_hardening_menu
        ;;
      0) return ;;
    esac
  done
}

# --- HARDENING MENU ---
show_hardening_menu() {
  while true; do
    CHOICE=$(whiptail --title "Node Hardening Controls" --menu "Manage Protection:" 28 78 18 \
      "1" "Force Cleanup (All Nodes)" \
      "2" "Re-apply Log Limits (OCI: 200M cap)" \
      "2b" "Validate/Repair logrotate rsyslog (T-305)" \
      "3" "Re-deploy Health Watchdog (T-306)" \
      "4" "Verify Control Plane Config (T-192)" \
      "5" "Re-apply Control Plane Hardening (T-192)" \
      "6" "Vacuum Old Journals (All Nodes, >7d)" \
      "7" "Vacuum Old Journals (Single Node)" \
      "8" "🔥 Firewall UFW — ssdnodes-6a12f10c9ef11 (Status)" \
      "9" "🔥 Firewall UFW — ssdnodes-6a12f10c9ef11 (Aplicar Regras)" \
      "10" "🚀 Deploy K8s Dashboard — SSDNodes (k8s.ssdnodes.dnor.io)" \
      "11" "🚀 Deploy Kubecost — SSDNodes (cost.ssdnodes.dnor.io)" \
      "12" "📋 Status componentes SSDNodes" \
      "13" "🔐 SSDNodes SSH harden + fail2ban (T-320a)" \
      "14" "👁 Dashboard view-only RBAC (T-320d)" \
      "15" "🔬 Deploy SonarQube CE — SSDNodes (T-341)" \
      "16" "⚙️ Deploy Jenkins — SSDNodes (T-341)" \
      "17" "🚀 Deploy CI Platform — Sonar+Jenkins (T-341)" \
      "0" "Back" 3>&1 1>&2 2>&3)
    
    if [ $? != 0 ]; then return; fi

    case "$CHOICE" in
      1) 
        echo -e "\n🧹 Triggering Manual Cleanup on ALL nodes..."
        for node in "${CLUSTER_NODES[@]}"; do
             ssh -t -o StrictHostKeyChecking=no "$node" "sudo /usr/local/bin/clean_node.sh --deep"
        done
        read -p "Press Enter..." 
        ;;
      2) 
        ./scripts/hardening/configure_log_limits.sh
        read -p "Press Enter..." 
        ;;
      2b)
        echo -e "\n🔍 Logrotate rsyslog (T-305)..."
        read -p "Dry-run only? (Y/n): " DRY
        if [[ "${DRY:-Y}" =~ ^[nN]$ ]]; then
          ./scripts/hardening/repair_logrotate_rsyslog.sh
        else
          ./scripts/hardening/repair_logrotate_rsyslog.sh --dry-run
        fi
        read -p "Press Enter..."
        ;;
      3)
        ./scripts/observability/install_health_watchdog.sh
        read -p "Press Enter..." 
        ;;
      4)
        # T-192: Verifica sincronia entre cluster live e IaC esperada
        echo -e "\n🔍 Control Plane Config Verification (T-192)..."
        echo ""
        echo "--- kube-apiserver: livenessProbe ---"
        ssh -o StrictHostKeyChecking=no oci-k8s-master \
          'sudo grep -A6 livenessProbe /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || echo "❌ AUSENTE"'
        echo ""
        echo "--- kube-apiserver: request throttling ---"
        ssh -o StrictHostKeyChecking=no oci-k8s-master \
          'sudo grep "max-requests\|max-mutating" /etc/kubernetes/manifests/kube-apiserver.yaml 2>/dev/null || echo "❌ AUSENTE"'
        echo ""
        echo "--- etcd: compaction + quota ---"
        ssh -o StrictHostKeyChecking=no oci-k8s-master \
          'sudo grep "auto-compaction\|quota-backend" /etc/kubernetes/manifests/etcd.yaml 2>/dev/null || echo "❌ AUSENTE"'
        echo ""
        echo "--- cilium: operator-num-workers ---"
        kubectl get cm -n kube-system cilium-config \
          -o jsonpath='{.data.operator-num-workers}' 2>/dev/null \
          && echo " (esperado: 2)" || echo "❌ não encontrado"
        echo ""
        echo "--- nodes: CPU e memória ---"
        kubectl top nodes 2>/dev/null
        read -p "Press Enter..."
        ;;
      5)
        # T-192: Re-aplica hardening do control plane via IaC
        echo -e "\n🛡️  Re-applying Control Plane Hardening (T-192)..."
        echo "⚠️  Isso irá reiniciar kube-apiserver e etcd (kubelet detecta mudanças)"
        read -p "Confirmar? (s/N): " CONFIRM
        if [[ "$CONFIRM" =~ ^[sS]$ ]]; then
          scp -o StrictHostKeyChecking=no \
            "$(dirname "$0")/../components/kube-system/commands.sh" \
            oci-k8s-master:/tmp/tune_control_plane.sh
          ssh -o StrictHostKeyChecking=no oci-k8s-master \
            'sudo chmod +x /tmp/tune_control_plane.sh && sudo /tmp/tune_control_plane.sh && rm /tmp/tune_control_plane.sh'
          echo "✅ Control plane hardening re-aplicado."
        else
          echo "Cancelado."
        fi
        read -p "Press Enter..."
        ;;
      6)
        # T-293: Emergency vacuum — remove archived journals >7d from ALL nodes
        # Prevents coroot-node-agent from re-reading GB of old archives on restart
        echo -e "\n🗑️  Vacuum Old Journals (All Nodes, cutoff=7d)..."
        ./scripts/hardening/vacuum_journals.sh
        read -p "Press Enter..."
        ;;
      7)
        # T-293: Emergency vacuum for a single node (interactive selection)
        NODE=$(whiptail --title "Select Node" --menu "Vacuum journals on which node?" 15 60 5 \
          "oci-k8s-master"  "Control Plane" \
          "oci-k8s-node-1"  "Worker 1" \
          "oci-k8s-node-2"  "Worker 2" \
          "oci-k8s-node-3"  "Worker 3" \
          "0" "Cancel" 3>&1 1>&2 2>&3)
        if [ $? != 0 ] || [ "$NODE" = "0" ]; then
          echo "Cancelado."; read -p "Press Enter..."
        else
          CUTOFF=$(whiptail --inputbox "Vacuum journals older than (e.g. 7d, 3d, 1d):" 8 50 "7d" \
            --title "Cutoff Time" 3>&1 1>&2 2>&3)
          [ $? != 0 ] && CUTOFF="7d"
          echo -e "\n🗑️  Vacuum Old Journals on ${NODE} (cutoff=${CUTOFF})..."
          ./scripts/hardening/vacuum_journals.sh "$NODE" "$CUTOFF"
        fi
        read -p "Press Enter..."
        ;;
      8)
        # Firewall UFW — ssdnodes-monstro: Status
        clear
        bash "$SCRIPT_DIR/scripts/hardening/ufw_manager.sh" --host ssdnodes-monstro --status
        read -p "Press Enter..."
        ;;
      9)
        # Firewall UFW — ssdnodes-monstro: Aplicar regras completas
        clear
        echo -e "${YELLOW}⚠️  Porta 22 permanece aberta (safety net).${NC}"
        echo -e "${YELLOW}    Todas as outras conexões da internet serão bloqueadas.${NC}"
        echo ""
        if whiptail --title "Firewall UFW — ssdnodes-monstro" \
            --yesno "Aplicar regras UFW em ssdnodes-monstro?\n\n- Porta 22: ABERTA para qualquer IP\n- Portas 80/443: só IPs autorizados\n- Porta 6443: só admin IP\n- Todo o resto: BLOQUEADO" \
            15 65; then
            bash "$SCRIPT_DIR/scripts/hardening/ufw_manager.sh" --host ssdnodes-monstro --apply
        else
            echo "Cancelado."
        fi
        read -p "Press Enter..."
        ;;
      10)
        # Deploy Kubernetes Dashboard no ssdnodes-monstro
        clear
        echo -e "${GREEN}🚀 Deploy Kubernetes Dashboard → k8s.ssdnodes.dnor.io${NC}"
        echo ""
        bash "$SCRIPT_DIR/scripts/ssdnodes/deploy_ssdnodes_components.sh" dashboard
        read -p "Press Enter..."
        ;;
      11)
        # Deploy Kubecost no ssdnodes-monstro
        clear
        echo -e "${GREEN}🚀 Deploy Kubecost Free → cost.ssdnodes.dnor.io${NC}"
        echo ""
        bash "$SCRIPT_DIR/scripts/ssdnodes/deploy_ssdnodes_components.sh" kubecost
        read -p "Press Enter..."
        ;;
      12)
        # Status dos componentes ssdnodes
        clear
        echo -e "${GREEN}📋 Status componentes ssdnodes-monstro${NC}"
        echo ""
        bash "$SCRIPT_DIR/scripts/ssdnodes/deploy_ssdnodes_components.sh" status
        read -p "Press Enter..."
        ;;
      13)
        echo -e "\n${YELLOW}T-320a: SSH hardening + fail2ban em ssdnodes-monstro${NC}"
        bash "$SCRIPT_DIR/scripts/hardening/ssh_harden_ssdnodes.sh" --host ssdnodes-6a12f10c9ef11 --dry-run
        read -p "Aplicar SSH hardening? (y/N): " SSH_CONFIRM
        if [[ "$SSH_CONFIRM" =~ ^[Yy]$ ]]; then
          bash "$SCRIPT_DIR/scripts/hardening/ssh_harden_ssdnodes.sh" --host ssdnodes-6a12f10c9ef11 --apply
        fi
        bash "$SCRIPT_DIR/scripts/hardening/fail2ban_ssdnodes.sh" --host ssdnodes-6a12f10c9ef11 --apply
        read -p "Press Enter..."
        ;;
      14)
        echo -e "\n${YELLOW}T-320d: Dashboard view-only RBAC${NC}"
        bash "$SCRIPT_DIR/scripts/ssdnodes/patch_dashboard_view_rbac.sh" --apply
        bash "$SCRIPT_DIR/scripts/ssdnodes/patch_dashboard_view_rbac.sh" --verify
        read -p "Press Enter..."
        ;;
      15)
        clear
        echo -e "${GREEN}🔬 Deploy SonarQube CE → sonar.ssdnodes.dnor.io (T-341)${NC}"
        echo -e "${YELLOW}Pré-requisito: Secret sonarqube-db-credentials (create_sonar_ci_secrets.sh)${NC}"
        bash "$SCRIPT_DIR/scripts/ssdnodes/deploy_ssdnodes_components.sh" sonarqube
        read -p "Press Enter..."
        ;;
      16)
        clear
        echo -e "${GREEN}⚙️ Deploy Jenkins → jenkins.ssdnodes.dnor.io (T-341)${NC}"
        bash "$SCRIPT_DIR/scripts/ssdnodes/deploy_ssdnodes_components.sh" jenkins
        read -p "Press Enter..."
        ;;
      17)
        clear
        echo -e "${GREEN}🚀 Deploy CI Platform (Sonar + Jenkins) — T-341${NC}"
        bash "$SCRIPT_DIR/scripts/ssdnodes/deploy_ssdnodes_components.sh" ci-platform
        read -p "Press Enter..."
        ;;
    esac
  done
}

# ==============================================================================
# 🚀 App Deploy Menu (T-115)
# Descobre apps dynamicamente via deploy.sh/publish.sh + mostra status do pod
# ==============================================================================
_app_get_label() {
  # Extrai o valor do label app: do primeiro yaml em k8s/ (excluindo subpastas minikube)
  local app_dir="$1"
  local yaml
  yaml=$(find "$app_dir/k8s" -maxdepth 1 -name "*.yaml" 2>/dev/null | head -1)
  [ -n "$yaml" ] || return 0
  grep -m1 "app:" "$yaml" 2>/dev/null | awk '{print $2}' | tr -d '"'
}

_app_cluster_access_state() {
  if run_kubectl_silent "get ns default -o name" >/dev/null 2>&1; then
    echo "available"
  else
    echo "kubectl unavailable"
  fi
}

_app_classify_pod_status_json() {
  local pods_json="$1"

  printf '%s' "$pods_json" | jq -r '
    def ready_flags: [.items[].status.containerStatuses[]?.ready];
    def waiting_reasons: [.items[].status.containerStatuses[]?.state.waiting.reason // empty];
    def terminated_reasons: [.items[].status.containerStatuses[]?.state.terminated.reason // empty];
    def crash_reasons:
      (waiting_reasons + terminated_reasons)
      | map(select(test("CrashLoopBackOff|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|RunContainerError|Error")));
    def phases: [.items[].status.phase // empty];
    if (.items | length) == 0 then "Missing"
    elif (crash_reasons | length) > 0 then "CrashLoop"
    elif (phases | any(. == "Pending")) then "Pending"
    elif ((ready_flags | length) > 0 and (ready_flags | all(. == true)) and (phases | length) > 0 and (phases | all(. == "Running"))) then "Running"
    elif (phases | any(. == "Running")) then "Pending"
    else ((phases | map(select(length > 0)) | first) // "Unknown")
    end
  ' 2>/dev/null || echo "Unknown"
}

_app_get_status() {
  local app_label="$1"
  local app_kind="${2:-workload}"
  local cluster_state="${3:-available}"
  if [ "$app_kind" = "static" ]; then
    echo "static/minio"
    return
  fi
  if [ "$cluster_state" != "available" ]; then
    echo "$cluster_state"
    return
  fi
  if [ -z "$app_label" ]; then echo "Missing"; return; fi

  local pods_json
  if ! pods_json=$(run_kubectl_silent "get pods -A -l app=$app_label -o json"); then
    echo "kubectl unavailable"
    return
  fi

  _app_classify_pod_status_json "$pods_json"
}

_app_deploy_logs_dir() {
  echo "${TUI_APP_DEPLOY_LOG_DIR:-$SCRIPT_DIR/../logs/tui-app-deploy}"
}

_app_local_bash() {
  if [ -x /usr/bin/bash ]; then
    echo "/usr/bin/bash"
  elif [ -x /bin/bash ]; then
    echo "/bin/bash"
  else
    echo "bash"
  fi
}

_app_slugify() {
  local value="${1:-unknown}"
  value=$(echo "$value" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]._-' '-')
  value="${value#-}"
  value="${value%-}"
  [ -n "$value" ] && echo "$value" || echo "unknown"
}

_app_new_deploy_log_file() {
  local app_name="$1"
  local script_name="$2"
  local logs_dir
  logs_dir=$(_app_deploy_logs_dir)
  mkdir -p "$logs_dir"
  printf "%s/%s_%s_%s.log\n" \
    "$logs_dir" \
    "$(date +%Y%m%d_%H%M%S)" \
    "$(_app_slugify "$app_name")" \
    "$(_app_slugify "${script_name%.sh}")"
}

_app_log_line() {
  local log_file="$1"
  shift
  printf '%s\n' "$*" | tee -a "$log_file"
}

_app_init_deploy_log() {
  local log_file="$1"
  local app_name="$2"
  local app_dir="$3"
  local deploy_script="$4"

  : > "$log_file"
  _app_log_line "$log_file" "=== TUI App Deploy Execution Log ==="
  _app_log_line "$log_file" "Started: $(date -Iseconds)"
  _app_log_line "$log_file" "App: $app_name"
  _app_log_line "$log_file" "Directory: $app_dir"
  _app_log_line "$log_file" "Script: $(basename "$deploy_script")"
  _app_log_line "$log_file" "Log file: $log_file"
  _app_log_line "$log_file" "---"
}

_app_check_oci_builder_logged() {
  local log_file="$1"

  _app_log_line "$log_file" "Checking docker/buildx builder: oci-builder"
  if ! command -v docker >/dev/null 2>&1; then
    _app_log_line "$log_file" "ERROR: docker not found in PATH"
    return 127
  fi

  set +e
  docker buildx inspect oci-builder 2>&1 | tee -a "$log_file"
  local status=${PIPESTATUS[0]}
  set -e
  return "$status"
}

_app_run_setup_dev_deploy_logged() {
  local log_file="$1"
  local setup_script="$SCRIPT_DIR/scripts/setup-dev-deploy.sh"
  local bash_bin
  bash_bin=$(_app_local_bash)

  _app_log_line "$log_file" "Running setup helper: $setup_script"
  set +e
  "$bash_bin" "$setup_script" 2>&1 | tee -a "$log_file"
  local status=${PIPESTATUS[0]}
  set -e

  if [ "$status" -eq 0 ]; then
    export KUBECONFIG="$SCRIPT_DIR/kubeconfig_tunnel.yaml"
    _app_log_line "$log_file" "Exported KUBECONFIG=$KUBECONFIG"
  fi

  return "$status"
}

_app_wait_for_nexus_ready_logged() {
  local log_file="$1"
  local max_attempts="${TUI_APP_NEXUS_READY_ATTEMPTS:-18}"
  local sleep_seconds="${TUI_APP_NEXUS_READY_SLEEP_SECONDS:-10}"

  _app_log_line "$log_file" "Checking Nexus registry readiness before deploy"

  local attempt=1
  while [ "$attempt" -le "$max_attempts" ]; do
    local pod_name
    local pod_phase
    local pod_ready

    pod_name=$(run_kubectl_silent "get pods -n nexus -l app=nexus -o jsonpath='{.items[0].metadata.name}'" | tr -d '\r')
    if [ -n "$pod_name" ]; then
      pod_phase=$(run_kubectl_silent "get pod -n nexus $pod_name -o jsonpath='{.status.phase}'" | tr -d '\r')
      pod_ready=$(run_kubectl_silent "get pod -n nexus $pod_name -o jsonpath='{.status.containerStatuses[0].ready}'" | tr -d '\r')

      if [ "$pod_phase" = "Running" ] && [ "$pod_ready" = "true" ]; then
        if run_kubectl_silent "exec -n nexus $pod_name -- curl -fsS http://127.0.0.1:8081/service/rest/v1/status" >/dev/null 2>&1; then
          _app_log_line "$log_file" "OK: Nexus registry API is ready"
          return 0
        fi
      fi
    fi

    _app_log_line "$log_file" "Waiting for Nexus API... ($attempt/$max_attempts) pod=${pod_name:-missing} phase=${pod_phase:-unknown} ready=${pod_ready:-false}"
    sleep "$sleep_seconds"
    attempt=$((attempt + 1))
  done

  _app_log_line "$log_file" "ERROR: Nexus registry API did not become ready in time"
  return 1
}

_app_run_deploy_logged() {
  local app_name="$1"
  local app_dir="$2"
  local deploy_script="$3"
  local log_file="$4"
  local script_name
  local bash_bin
  script_name="$(basename "$deploy_script")"
  bash_bin=$(_app_local_bash)

  _app_log_line "$log_file" "Running deploy command: cd $app_dir && $bash_bin $script_name"
  _app_log_line "$log_file" "---"

  set +e
  (
    cd "$app_dir"
    "$bash_bin" "$script_name"
  ) 2>&1 | tee -a "$log_file"
  local status=${PIPESTATUS[0]}
  set -e

  _app_log_line "$log_file" "---"
  _app_log_line "$log_file" "Finished: $(date -Iseconds)"
  _app_log_line "$log_file" "Exit code: $status"

  return "$status"
}

_app_has_npm_script() {
  local app_dir="$1"
  local script_name="$2"
  local package_json="$app_dir/package.json"

  [ -f "$package_json" ] || return 1
  jq -er --arg script_name "$script_name" '.scripts[$script_name] // empty' "$package_json" >/dev/null 2>&1
}

_app_static_upload_endpoint_url() {
  echo "${STATIC_UPLOAD_ENDPOINT_URL:-https://minio.dnor.io}"
}

_app_static_upload_endpoint_host() {
  local endpoint_url
  local endpoint_host

  endpoint_url=$(_app_static_upload_endpoint_url)
  endpoint_host="${endpoint_url#*://}"
  endpoint_host="${endpoint_host%%/*}"
  endpoint_host="${endpoint_host%%:*}"

  echo "$endpoint_host"
}

_app_static_ca_bundle() {
  if [ -n "${AWS_CA_BUNDLE:-}" ]; then
    echo "$AWS_CA_BUNDLE"
    return
  fi

  local default_ca_bundle="$SCRIPT_DIR/dnor-ca-issuer.crt"
  if [ -f "$default_ca_bundle" ]; then
    echo "$default_ca_bundle"
  fi
}

_app_static_minio_credentials() {
  if [ -n "${MINIO_ACCESS_KEY:-}" ] && [ -n "${MINIO_SECRET_KEY:-}" ]; then
    echo "${MINIO_ACCESS_KEY}|${MINIO_SECRET_KEY}"
    return 0
  fi

  if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo "${AWS_ACCESS_KEY_ID}|${AWS_SECRET_ACCESS_KEY}"
    return 0
  fi

  minio_get_credentials 2>/dev/null
}

_app_check_static_prereqs_logged() {
  local app_dir="$1"
  local log_file="$2"

  _app_log_line "$log_file" "Checking static deploy prerequisites"

  local cmd
  local missing=0
  local endpoint_url
  local endpoint_host
  local ca_bundle
  local minio_creds

  endpoint_url=$(_app_static_upload_endpoint_url)
  endpoint_host=$(_app_static_upload_endpoint_host)
  ca_bundle=$(_app_static_ca_bundle)
  minio_creds=$(_app_static_minio_credentials || true)

  for cmd in node npm aws jq; do
    if command -v "$cmd" >/dev/null 2>&1; then
      _app_log_line "$log_file" "OK: $cmd found at $(command -v "$cmd")"
    else
      _app_log_line "$log_file" "ERROR: $cmd not found in PATH"
      missing=1
    fi
  done

  if [ ! -f "$app_dir/package.json" ]; then
    _app_log_line "$log_file" "ERROR: package.json not found in $app_dir"
    return 1
  fi

  if ! _app_has_npm_script "$app_dir" "build-and-upload"; then
    _app_log_line "$log_file" "ERROR: npm script build-and-upload not found in $app_dir/package.json"
    return 1
  fi

  _app_log_line "$log_file" "Static upload endpoint: $endpoint_url"

  if [ -z "$endpoint_host" ]; then
    _app_log_line "$log_file" "ERROR: could not determine host from static upload endpoint"
    missing=1
  fi

  if command -v getent >/dev/null 2>&1; then
    if getent hosts "$endpoint_host" >/dev/null 2>&1; then
      _app_log_line "$log_file" "OK: $endpoint_host resolves locally"
    else
      _app_log_line "$log_file" "ERROR: $endpoint_host is not resolvable on this host"
      missing=1
    fi
  fi

  case "$endpoint_url" in
    https://*)
      if [ -n "${AWS_CA_BUNDLE:-}" ] && [ ! -f "${AWS_CA_BUNDLE}" ]; then
        _app_log_line "$log_file" "ERROR: AWS_CA_BUNDLE points to a missing file: ${AWS_CA_BUNDLE}"
        missing=1
      elif [ -n "$ca_bundle" ]; then
        _app_log_line "$log_file" "OK: CA bundle available at $ca_bundle"
      else
        _app_log_line "$log_file" "WARN: no CA bundle configured for HTTPS endpoint; host trust must already be installed"
      fi
      ;;
  esac

  if [ -n "$minio_creds" ]; then
    _app_log_line "$log_file" "OK: MinIO credentials available for static upload"
  else
    _app_log_line "$log_file" "ERROR: could not resolve MinIO credentials for static upload"
    missing=1
  fi

  [ "$missing" -eq 0 ]
}

_app_run_npm_script_logged() {
  local app_name="$1"
  local app_dir="$2"
  local script_name="$3"
  local log_file="$4"
  local minio_creds
  local minio_access_key
  local minio_secret_key

  _app_log_line "$log_file" "Running static deploy command: cd $app_dir && npm run $script_name"
  _app_log_line "$log_file" "---"

  minio_creds=$(_app_static_minio_credentials || true)
  if [ -z "$minio_creds" ]; then
    _app_log_line "$log_file" "ERROR: could not resolve MinIO credentials for static upload"
    _app_log_line "$log_file" "---"
    _app_log_line "$log_file" "Finished: $(date -Iseconds)"
    _app_log_line "$log_file" "Exit code: 1"
    return 1
  fi

  minio_access_key="${minio_creds%%|*}"
  minio_secret_key="${minio_creds#*|}"

  set +e
  (
    cd "$app_dir"
    export MINIO_ACCESS_KEY="$minio_access_key"
    export MINIO_SECRET_KEY="$minio_secret_key"
    export AWS_ACCESS_KEY_ID="$minio_access_key"
    export AWS_SECRET_ACCESS_KEY="$minio_secret_key"
    unset AWS_PROFILE AWS_DEFAULT_PROFILE AWS_SESSION_TOKEN
    npm run "$script_name"
  ) 2>&1 | tee -a "$log_file"
  local status=${PIPESTATUS[0]}
  set -e

  _app_log_line "$log_file" "---"
  _app_log_line "$log_file" "Finished: $(date -Iseconds)"
  _app_log_line "$log_file" "Exit code: $status"

  return "$status"
}

_app_action_menu() {
  local app_name="$1"
  local app_dir="$2"
  local app_label="$3"
  local app_kind="${4:-workload}"
  local cluster_state="${5:-available}"

  local deploy_script="$app_dir/deploy.sh"
  [ -f "$deploy_script" ] || deploy_script="$app_dir/publish.sh"

  while true; do
    # Status atualizado a cada entrada no submenu
    local pod_status
    pod_status=$(_app_get_status "$app_label" "$app_kind" "$cluster_state")

    local actions
    local header
    if [ "$app_kind" = "static" ]; then
      actions="🚀 Build + Upload Static
📂 Show dist files
← Back"
      header="App: $app_name  |  Target: s3://my-site/static/"
    elif [ "$cluster_state" != "available" ]; then
      actions="🚀 Deploy / Rebuild
← Back"
      header="App: $app_name  |  Cluster: $cluster_state"
    elif [ -z "$app_label" ]; then
      actions="🚀 Deploy / Rebuild
← Back"
      header="App: $app_name  |  Pod: Missing (no app label)"
    else
      actions="🚀 Deploy / Rebuild
📋 Rollout Status
📜 View Logs (tail -200)
🔄 Restart Deployment
← Back"
      header="App: $app_name  |  Pod: $pod_status"
    fi

    local selected
    selected=$(echo "$actions" | "$FZF_BIN" \
      --height=40% --layout=reverse --border \
      --prompt="$app_name > " \
      --header="$header") || true
    [ -z "$selected" ] && return

    case "$selected" in
      "🚀 Build + Upload Static")
        local static_log_file
        static_log_file=$(_app_new_deploy_log_file "$app_name" "build-and-upload")
        APP_DEPLOY_LAST_LOG_FILE="$static_log_file"
        _app_init_deploy_log "$static_log_file" "$app_name" "$app_dir" "npm run build-and-upload"

        if ! _app_check_static_prereqs_logged "$app_dir" "$static_log_file"; then
          echo -e "\n${RED}❌ Static deploy prerequisites failed${NC}"
          echo -e "${GRAY}Log saved to: $static_log_file${NC}"
          read -p "$(t "press_enter")"
          continue
        fi

        clear
        echo -e "${CYAN}📦 Building and uploading static assets for $app_name...${NC}"
        echo -e "${GRAY}Log: $static_log_file${NC}"
        echo ""
        if _app_run_npm_script_logged "$app_name" "$app_dir" "build-and-upload" "$static_log_file"; then
          echo -e "\n${GREEN}✅ Static assets uploaded successfully${NC}"
        else
          echo -e "\n${RED}❌ Static deploy failed — check output above${NC}"
        fi
        echo -e "${GRAY}Log saved to: $static_log_file${NC}"
        read -p "$(t "press_enter")"
        ;;
      "🚀 Deploy / Rebuild")
        local deploy_log_file
        deploy_log_file=$(_app_new_deploy_log_file "$app_name" "$(basename "$deploy_script")")
        APP_DEPLOY_LAST_LOG_FILE="$deploy_log_file"
        _app_init_deploy_log "$deploy_log_file" "$app_name" "$app_dir" "$deploy_script"

        # Verificar oci-builder antes de buildar
        if ! _app_check_oci_builder_logged "$deploy_log_file"; then
          echo -e "${YELLOW}⚠️  oci-builder não encontrado.${NC}"
          echo -e "${GRAY}Log: $deploy_log_file${NC}"
          read -p "Executar setup-dev-deploy.sh? [y/N] " yn
          _app_log_line "$deploy_log_file" "User response to setup-dev-deploy prompt: ${yn:-N}"
          if [[ "$yn" =~ ^[Yy]$ ]]; then
            if ! _app_run_setup_dev_deploy_logged "$deploy_log_file"; then
              echo -e "\n${RED}❌ setup-dev-deploy.sh failed${NC}"
              echo -e "${GRAY}Log saved to: $deploy_log_file${NC}"
              read -p "$(t "press_enter")"
              continue
            fi
            if ! _app_check_oci_builder_logged "$deploy_log_file"; then
              echo -e "\n${RED}❌ oci-builder ainda indisponível após setup${NC}"
              echo -e "${GRAY}Log saved to: $deploy_log_file${NC}"
              read -p "$(t "press_enter")"
              continue
            fi
          else
            _app_log_line "$deploy_log_file" "Setup helper skipped by user."
            echo -e "${GRAY}Log saved to: $deploy_log_file${NC}"
            read -p "$(t "press_enter")"
            continue
          fi
        fi
        clear
        echo -e "${CYAN}🚀 Deploying $app_name...${NC}"
        echo -e "${GRAY}Log: $deploy_log_file${NC}"
        echo ""
        if ! _app_wait_for_nexus_ready_logged "$deploy_log_file"; then
          echo -e "\n${RED}❌ Nexus registry is not ready for image push${NC}"
          echo -e "${GRAY}Log saved to: $deploy_log_file${NC}"
          read -p "$(t "press_enter")"
          continue
        fi
        if _app_run_deploy_logged "$app_name" "$app_dir" "$deploy_script" "$deploy_log_file"; then
          echo -e "\n${GREEN}✅ $app_name deployed successfully${NC}"
        else
          echo -e "\n${RED}❌ Deploy failed — check output above${NC}"
        fi
        echo -e "${GRAY}Log saved to: $deploy_log_file${NC}"
        read -p "$(t "press_enter")"
        ;;
      "📂 Show dist files")
        clear
        echo -e "${CYAN}📂 dist/ preview: $app_name${NC}"
        echo ""
        if [ -d "$app_dir/dist" ]; then
          find "$app_dir/dist" -maxdepth 2 -type f | sort | sed -n '1,200p'
        else
          echo "dist/ not found yet. Run build/upload first."
        fi
        echo ""
        read -p "$(t "press_enter")"
        ;;
      "📋 Rollout Status")
        clear
        echo -e "${CYAN}📋 Rollout status: $app_name${NC}"
        echo ""
        run_kubectl "rollout status deployment -l app=$app_label -n default" 2>/dev/null || \
          run_kubectl "get deployment -l app=$app_label -A -o wide" 2>/dev/null || \
          echo "No deployment found for app=$app_label"
        echo ""
        read -p "$(t "press_enter")"
        ;;
      "📜 View Logs (tail -200)")
        run_kubectl "logs -l app=$app_label -n default --tail=200 -f" 2>/dev/null | less -SR || true
        ;;
      "🔄 Restart Deployment")
        echo -e "${YELLOW}Restarting $app_name...${NC}"
        if run_kubectl "rollout restart deployment -l app=$app_label -n default" 2>/dev/null; then
          echo -e "${GREEN}✅ Restart triggered${NC}"
        else
          echo -e "${RED}❌ No deployment found for app=$app_label${NC}"
        fi
        read -p "$(t "press_enter")"
        ;;
      *) return ;;
    esac
  done
}

app_deploy_menu() {
  local apps_dir="$SCRIPT_DIR/../apps"

  while true; do
    local cluster_state
    cluster_state=$(_app_cluster_access_state)

    # Descobrir apps com deploy.sh ou publish.sh
    local app_names=()
    local app_dirs=()
    local app_labels=()
    local app_kinds=()
    for script in "$apps_dir"/*/deploy.sh "$apps_dir"/*/publish.sh; do
      [ -f "$script" ] || continue
      local dir
      dir="$(dirname "$script")"
      local name
      name="$(basename "$dir")"
      # Evitar duplicatas (caso tenha ambos deploy.sh e publish.sh)
      local already=0
      for n in "${app_names[@]:-}"; do [[ "$n" == "$name" ]] && already=1 && break; done
      [ "$already" -eq 1 ] && continue
      app_names+=("$name")
      app_dirs+=("$dir")
      app_labels+=("$(_app_get_label "$dir")")
      app_kinds+=("workload")
    done

    for package_json in "$apps_dir"/*/package.json; do
      [ -f "$package_json" ] || continue
      local dir
      dir="$(dirname "$package_json")"
      local name
      name="$(basename "$dir")"
      local already=0
      for n in "${app_names[@]:-}"; do [[ "$n" == "$name" ]] && already=1 && break; done
      [ "$already" -eq 1 ] && continue
      _app_has_npm_script "$dir" "build-and-upload" || continue
      app_names+=("$name")
      app_dirs+=("$dir")
      app_labels+=("$(_app_get_label "$dir")")
      app_kinds+=("static")
    done

    if [ ${#app_names[@]} -eq 0 ]; then
      echo -e "${YELLOW}Nenhum app deployável encontrado em $apps_dir${NC}"
      read -p "$(t "press_enter")"
      return
    fi

    # Construir lista com status em linha (leitura rápida em paralelo)
    local menu_items="← Back\n"
    for i in "${!app_names[@]}"; do
      local lbl="${app_labels[$i]:-?}"
      local kind="${app_kinds[$i]:-workload}"
      local pod_status
      pod_status=$(_app_get_status "$lbl" "$kind" "$cluster_state")
      local icon="⬜"
      if [ "$kind" = "static" ]; then
        icon="📦"
      else
        case "$pod_status" in
          "Running") icon="🟢" ;;
          "Pending") icon="🟡" ;;
          "CrashLoop") icon="🔴" ;;
          "Missing") icon="⬜" ;;
          "kubectl unavailable") icon="⚪" ;;
          *) icon="❓" ;;
        esac
      fi
      menu_items+="${icon} ${app_names[$i]}  [${pod_status}]\n"
    done

    local selected
    selected=$(printf "%b" "$menu_items" | "$FZF_BIN" \
      --height=60% --layout=reverse --border \
      --prompt="Deploy App > " \
      --header="$(printf '%-4s %-25s %s | Cluster: %s' 'ST' 'APP' 'POD STATUS' "$cluster_state")") || true

    [ -z "$selected" ] || [[ "$selected" == "← Back" ]] && return

    # Extrair nome do app (remover ícone e status)
    local chosen_name
    chosen_name=$(echo "$selected" | awk '{print $2}')

    # Encontrar índice
    local idx=-1
    for i in "${!app_names[@]}"; do
      [[ "${app_names[$i]}" == "$chosen_name" ]] && idx=$i && break
    done
    [ "$idx" -ge 0 ] || continue

    _app_action_menu "${app_names[$idx]}" "${app_dirs[$idx]}" "${app_labels[$idx]}" "${app_kinds[$idx]}" "$cluster_state"
  done
}

_jslibs_dir() {
  echo "${JSLIBS_DIR:-$HOME/js-libs}"
}

_jslibs_logs_dir() {
  echo "${TUI_JSLIBS_LOG_DIR:-$SCRIPT_DIR/../logs/tui-jslibs}"
}

_jslibs_new_log_file() {
  local action="$1"
  local logs_dir
  logs_dir=$(_jslibs_logs_dir)
  mkdir -p "$logs_dir"
  printf "%s/%s_js-libs_%s.log\n" \
    "$logs_dir" \
    "$(date +%Y%m%d_%H%M%S)" \
    "$(_app_slugify "$action")"
}

_jslibs_require_workspace() {
  local dir="${1:-$(_jslibs_dir)}"

  if [ ! -d "$dir" ]; then
    echo -e "${RED}Error: Directory $dir not found.${NC}"
    echo "Clone ~/js-libs first and retry."
    return 1
  fi

  if [ ! -f "$dir/lerna.json" ]; then
    echo -e "${RED}Error: $dir/lerna.json not found.${NC}"
    return 1
  fi

  if [ ! -d "$dir/packages" ]; then
    echo -e "${RED}Error: $dir/packages not found.${NC}"
    return 1
  fi

  return 0
}

_jslibs_workspace_version() {
  local dir="${1:-$(_jslibs_dir)}"
  jq -r '.version // "unknown"' "$dir/lerna.json" 2>/dev/null || echo "unknown"
}

_jslibs_package_manifest_paths() {
  local dir="${1:-$(_jslibs_dir)}"
  find "$dir/packages" -mindepth 2 -maxdepth 2 -name package.json 2>/dev/null | sort
}

_jslibs_has_publish_auth() {
  local dir="${1:-$(_jslibs_dir)}"
  local npmrc="$dir/.npmrc"

  [ -f "$npmrc" ] || return 1
  grep -Eq '(^_auth(Token)?=|//[^[:space:]]+:_auth(Token)?=)' "$npmrc"
}

_jslibs_git_status() {
  local dir="${1:-$(_jslibs_dir)}"
  git -C "$dir" status --short 2>/dev/null || true
}

_jslibs_print_npmrc_redacted() {
  local npmrc_path="$1"
  sed -E \
    -e 's#(^_auth(Token)?=).*#\1[redacted]#' \
    -e 's#(//[^[:space:]]+:_auth(Token)?=).*#\1[redacted]#' \
    "$npmrc_path"
}

_jslibs_ensure_nexus_tunnel() {
  if lsof -i :8081 >/dev/null 2>&1; then
    return 0
  fi

  echo -e "${YELLOW}No Nexus tunnel detected on localhost:8081. Opening one now...${NC}"

  if ! run_kubectl_silent "get svc -n nexus nexus-service --no-headers" >/dev/null; then
    echo -e "${RED}Error: Unable to reach nexus-service via kubectl.${NC}"
    return 1
  fi

  local nexus_nodeport
  nexus_nodeport=$(run_kubectl "get svc -n nexus nexus-service -o jsonpath='{.spec.ports[?(@.port==8081)].nodePort}'" | tr -d "'\r\n")
  if [ -z "$nexus_nodeport" ]; then
    nexus_nodeport=$(run_kubectl "get svc -n nexus nexus-service -o jsonpath='{.spec.ports[0].nodePort}'" | tr -d "'\r\n")
  fi

  if [ -z "$nexus_nodeport" ]; then
    echo -e "${RED}Error: Could not determine Nexus NodePort.${NC}"
    return 1
  fi

  start_tunnel "nexus" "nexus-service" "8081" "$nexus_nodeport" "Nexus API tunnel" "true" "127.0.0.1" "127.0.0.1" "true"
}

_jslibs_prepare_nexus_access() {
  JSLIBS_NEXUS_PASSWORD=""

  _jslibs_ensure_nexus_tunnel || return 1

  JSLIBS_NEXUS_PASSWORD=$(nexus_get_admin_password 2>/dev/null || true)
  if [ -z "$JSLIBS_NEXUS_PASSWORD" ]; then
    echo -e "${RED}Error: Could not retrieve Nexus admin password.${NC}"
    return 1
  fi

  return 0
}

_jslibs_nexus_package_version() {
  local password="$1"
  local package_name="$2"
  local search_name="${package_name##*/}"
  local encoded_name
  encoded_name=$(jq -nr --arg value "$search_name" '$value | @uri')

  local response
  if ! response=$(curl -fsS -u "admin:$password" "$NEXUS_API_BASE/service/rest/v1/search?repository=npm-repo&format=npm&name=$encoded_name" 2>/dev/null); then
    echo "error"
    return 0
  fi

  local versions
  versions=$(printf '%s' "$response" | jq -r '.items[].version // empty' 2>/dev/null | sort -V || true)
  if [ -n "$versions" ]; then
    printf '%s\n' "$versions" | tail -n 1
  else
    echo "not found"
  fi
}

_jslibs_status_rows_from_dir() {
  local dir="$1"
  local password="$2"

  local manifest
  while IFS= read -r manifest; do
    [ -n "$manifest" ] || continue

    local package_name
    local local_version
    local nexus_version

    package_name=$(jq -r '.name // empty' "$manifest" 2>/dev/null)
    local_version=$(jq -r '.version // "unknown"' "$manifest" 2>/dev/null)
    [ -n "$package_name" ] || continue

    if [ -n "$password" ]; then
      nexus_version=$(_jslibs_nexus_package_version "$password" "$package_name")
    else
      nexus_version="unavailable"
    fi

    printf '%s|%s|%s\n' "$package_name" "$local_version" "$nexus_version"
  done < <(_jslibs_package_manifest_paths "$dir")
}

_jslibs_repo_status_from_json() {
  local repos_json="$1"

  local spec
  for spec in "npm-group|group" "npm-repo|hosted" "npm-proxy|proxy"; do
    local name="${spec%%|*}"
    local repo_type="${spec##*|}"
    local repo_url
    repo_url=$(printf '%s' "$repos_json" | jq -r --arg name "$name" --arg repo_type "$repo_type" '
      [.[] | select(.format == "npm" and .name == $name and .type == $repo_type)][0].url // empty
    ' 2>/dev/null)

    if [ -n "$repo_url" ]; then
      printf '%s\t%s\t%s\t%s\n' "$name" "OK" "$repo_type" "$repo_url"
    else
      printf '%s\t%s\t%s\t%s\n' "$name" "MISSING" "$repo_type" "-"
    fi
  done
}

_jslibs_run_logged() {
  local dir="$1"
  local action="$2"
  shift 2

  local log_file
  log_file=$(_jslibs_new_log_file "$action")

  : > "$log_file"
  _app_log_line "$log_file" "=== TUI js-libs Execution Log ==="
  _app_log_line "$log_file" "Started: $(date -Iseconds)"
  _app_log_line "$log_file" "Directory: $dir"
  _app_log_line "$log_file" "Action: $action"
  _app_log_line "$log_file" "Command: $*"
  _app_log_line "$log_file" "Log file: $log_file"
  _app_log_line "$log_file" "---"

  set +e
  (
    cd "$dir"
    "$@"
  ) 2>&1 | tee -a "$log_file"
  local status=${PIPESTATUS[0]}
  set -e

  _app_log_line "$log_file" "---"
  _app_log_line "$log_file" "Finished: $(date -Iseconds)"
  _app_log_line "$log_file" "Exit code: $status"

  echo ""
  if [ "$status" -eq 0 ]; then
    echo -e "${GREEN}✓ Action completed successfully${NC}"
  else
    echo -e "${RED}✗ Action failed with exit code $status${NC}"
  fi
  echo "Log: $log_file"

  return "$status"
}

jslibs_status() {
  local dir
  dir=$(_jslibs_dir)

  _jslibs_require_workspace "$dir" || {
    read -p "$(t 'press_enter')"
    return 1
  }

  _jslibs_prepare_nexus_access || {
    read -p "$(t 'press_enter')"
    return 1
  }

  local workspace_version
  workspace_version=$(_jslibs_workspace_version "$dir")

  clear
  echo -e "${BLUE}=== js-libs Status ===${NC}"
  echo "Workspace: $dir"
  echo "Monorepo version: $workspace_version"
  echo ""
  printf '%-28s %-12s %-12s\n' "PACKAGE" "LOCAL" "NEXUS"
  printf '%-28s %-12s %-12s\n' "-------" "-----" "-----"

  local found_any=false
  local row
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    found_any=true

    local package_name
    local local_version
    local nexus_version
    IFS='|' read -r package_name local_version nexus_version <<< "$row"
    printf '%-28s %-12s %-12s\n' "$package_name" "$local_version" "$nexus_version"
  done < <(_jslibs_status_rows_from_dir "$dir" "$JSLIBS_NEXUS_PASSWORD")

  if [ "$found_any" = false ]; then
    echo "No package manifests found under $dir/packages"
  fi

  echo ""
  read -p "$(t 'press_enter')"
}

jslibs_build_all() {
  local dir
  dir=$(_jslibs_dir)

  _jslibs_require_workspace "$dir" || {
    read -p "$(t 'press_enter')"
    return 1
  }

  clear
  echo -e "${BLUE}=== js-libs Build All ===${NC}"
  echo "Command: npx lerna run tsc"
  echo "Directory: $dir"
  echo ""
  local status=0
  _jslibs_run_logged "$dir" "build-all" npx lerna run tsc || status=$?

  if [ "$status" -eq 0 ]; then
    local git_status
    git_status=$(_jslibs_git_status "$dir")
    if [ -n "$git_status" ]; then
      echo ""
      echo -e "${YELLOW}Note: Build left uncommitted changes in $dir.${NC}"
      printf '%s\n' "$git_status" | head -n 20
    fi
  fi

  read -p "$(t 'press_enter')"
  return "$status"
}

jslibs_publish_all() {
  local dir
  dir=$(_jslibs_dir)

  _jslibs_require_workspace "$dir" || {
    read -p "$(t 'press_enter')"
    return 1
  }

  if ! _jslibs_has_publish_auth "$dir"; then
    clear
    echo -e "${RED}Error: Publish credentials not found in $dir/.npmrc${NC}"
    echo "Expected _auth, _authToken, or scoped auth entry before running publish."
    read -p "$(t 'press_enter')"
    return 1
  fi

  local git_status
  git_status=$(_jslibs_git_status "$dir")
  if [ -n "$git_status" ]; then
    clear
    echo -e "${YELLOW}Publish blocked: js-libs has uncommitted changes.${NC}"
    echo "Lerna publish from-package requires a clean worktree."
    echo "Resolve or commit the following files first:"
    printf '%s\n' "$git_status" | head -n 20
    echo ""
    read -p "$(t 'press_enter')"
    return 1
  fi

  clear
  echo -e "${BLUE}=== js-libs Publish All ===${NC}"
  echo "Command: npx lerna publish from-package --yes"
  echo "Directory: $dir"
  echo ""
  _jslibs_run_logged "$dir" "publish-all" npx lerna publish from-package --yes
  read -p "$(t 'press_enter')"
}

jslibs_check_nexus() {
  local dir
  dir=$(_jslibs_dir)

  _jslibs_require_workspace "$dir" || {
    read -p "$(t 'press_enter')"
    return 1
  }

  _jslibs_prepare_nexus_access || {
    read -p "$(t 'press_enter')"
    return 1
  }

  local repos_json
  if ! repos_json=$(curl -fsS -u "admin:$JSLIBS_NEXUS_PASSWORD" "$NEXUS_API_BASE/service/rest/v1/repositories" 2>/dev/null); then
    echo -e "${RED}Error: Failed to query Nexus repositories API.${NC}"
    read -p "$(t 'press_enter')"
    return 1
  fi

  clear
  echo -e "${BLUE}=== Nexus NPM Health ===${NC}"
  echo ""
  printf '%-12s %-10s %-10s %s\n' "REPOSITORY" "STATUS" "TYPE" "URL"
  printf '%-12s %-10s %-10s %s\n' "----------" "------" "----" "---"

  local row
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    local repo_name
    local status
    local repo_type
    local repo_url
    IFS=$'\t' read -r repo_name status repo_type repo_url <<< "$row"
    printf '%-12s %-10s %-10s %s\n' "$repo_name" "$status" "$repo_type" "$repo_url"
  done < <(_jslibs_repo_status_from_json "$repos_json")

  echo ""
  read -p "$(t 'press_enter')"
}

jslibs_show_npmrc() {
  local dir
  dir=$(_jslibs_dir)

  _jslibs_require_workspace "$dir" || {
    read -p "$(t 'press_enter')"
    return 1
  }

  local npmrc_path="$dir/.npmrc"

  clear
  echo -e "${BLUE}=== js-libs .npmrc ===${NC}"
  echo "Path: $npmrc_path"
  echo ""

  if [ ! -f "$npmrc_path" ]; then
    echo -e "${YELLOW}No .npmrc found at $npmrc_path${NC}"
    echo ""
    read -p "$(t 'press_enter')"
    return 0
  fi

  _jslibs_print_npmrc_redacted "$npmrc_path"
  echo ""
  read -p "$(t 'press_enter')"
}

jslibs_menu() {
  ensure_fzf

  local dir
  dir=$(_jslibs_dir)

  _jslibs_require_workspace "$dir" || {
    read -p "$(t 'press_enter')"
    return 1
  }

  while true; do
    local workspace_version
    workspace_version=$(_jslibs_workspace_version "$dir")

    local menu="1. Status: local vs Nexus
2. Build All (lerna run tsc)
3. Publish All (lerna publish from-package --yes)
4. Check Registry (npm-group / npm-repo / npm-proxy)
5. View current .npmrc
0. Back"

    local selected
    selected=$(echo "$menu" | "$FZF_BIN" \
      --height=45% \
      --layout=reverse \
      --border \
      --prompt="js-libs Manager > " \
      --header="Directory: $dir | Version: $workspace_version") || return 0

    case "${selected%%.*}" in
      1)
        jslibs_status
        ;;
      2)
        jslibs_build_all
        ;;
      3)
        jslibs_publish_all
        ;;
      4)
        jslibs_check_nexus
        ;;
      5)
        jslibs_show_npmrc
        ;;
      0)
        return 0
        ;;
    esac
  done
}

main_menu() {
  ensure_fzf
  
  # Run auto port forwarding on startup
  auto_forward_ports

  while true; do
    # Build port status header
    local port_status
    port_status=$(get_port_status)
    
    # Build menu with translated strings (HARDCODED ORDER - dynamic ordering disabled)
    local menu="$(t "menu_k9s")
$(t "menu_port_forward")
$(t "menu_service_config")
$(t "menu_credentials")
$(t "menu_components")
$(t "menu_deploy_apps")
$(t "menu_dashboard")
$(printf "$(t "menu_namespace")" "$CURRENT_NS")
$(t "menu_pod")
$(t "menu_all_pods")
$(t "menu_nodes")
$(t "menu_update")
$(t "menu_maintenance")
$(t "menu_security")
$(t "menu_backup")
$(t "menu_volumes")
$(t "menu_node_maintenance")
$(t "menu_kubecost")
$(t "menu_deepflow")
$(t "menu_deepflow_uninstall")
$(t "menu_pixie_install")
$(t "menu_pixie_uninstall")
$(t "menu_coroot_install")
$(t "menu_coroot_uninstall")
$(t "menu_parca_install")
$(t "menu_parca_uninstall")
$(t "menu_cloud_rescue")
$(t "menu_preferences")
$(t "menu_health")
$(t "menu_catalog")
$(t "menu_jslibs")
$(t "menu_bootstrap")
$(t "menu_exit")"

    local selected
    selected=$(echo "$menu" | "$FZF_BIN" --height=70% --layout=reverse --border --prompt="Main Menu (ESC to exit) > " --header="Cluster: $MASTER_NODE | $port_status") || true

    if [ -z "$selected" ]; then
      exit 0
    fi

    # Match action based on position number
    case "${selected%%.*}" in
      1)
        open_k9s
        ;;
      2)
        access_menu
        ;;
      3)
        service_config_menu
        ;;
      4)
        view_credentials_menu
        ;;
      5)
        component_management_menu
        ;;
      6)
        app_deploy_menu
        ;;
      7)
        open_dashboard
        ;;
      8)
        select_namespace
        ;;
      9)
        select_pod
        ;;
      10)
        clear
        run_kubectl "get pods -A -o wide" | less -S
        ;;
      11)
        # Node Status - Interactive Menu with fzf
        while true; do
          echo -e "${BLUE}📊 Node Status  (CPU requests: 🟢<75%  🟡75-85%  🔴≥85%)${NC}"
          echo ""

          # Collect CPU request % per node from a single describe call
          run_kubectl_silent "describe nodes" | awk '
            /^Name:/       { node=$2; in_a=0 }
            /^Allocated resources:/ { in_a=1 }
            /^Events:/     { in_a=0 }
            in_a && /^ *cpu / && /\(/ {
              pct=$3; gsub(/[()%]/,"",pct)
              print node, pct
              in_a=0
            }
          ' > /tmp/nodes_headroom_$$.txt 2>/dev/null || true

          # Build node list (pipe subshell reads headroom from file)
          run_kubectl "get nodes --no-headers" | while read -r name status roles age version rest; do
            local s_icon="❌"
            [[ "$status" == "Ready" ]] && s_icon="✅"
            [[ "$roles" == "<none>" ]] && roles="worker"
            local pct cpu_col="  ?"
            pct=$(grep "^${name} " /tmp/nodes_headroom_$$.txt 2>/dev/null | awk '{print $2}')
            if [[ -n "$pct" && "$pct" =~ ^[0-9]+$ ]]; then
              local icon="🟢"
              if   (( pct >= 85 )); then icon="🔴"
              elif (( pct >= 75 )); then icon="🟡"; fi
              cpu_col="${icon} ${pct}%"
            fi
            echo "$name|$s_icon|$status|$roles|$version|$age|$cpu_col"
          done > /tmp/nodes_$$.txt

          # Format for fzf (read from nodes_$$.txt, write to nodes_display_$$.txt)
          {
            printf "%-20s %-6s %-10s %-15s %-12s %-6s %s\n" "NODE" "ST" "CONDITION" "ROLE" "VERSION" "AGE" "CPU REQ"
            while IFS='|' read -r name icon status role version age cpu; do
              printf "%-20s %-6s %-10s %-15s %-12s %-6s %s\n" "$name" "$icon" "$status" "$role" "$version" "$age" "$cpu"
            done < /tmp/nodes_$$.txt
          } > /tmp/nodes_display_$$.txt

          # Use fzf with working preview
          local selected_node
          selected_node=$(cat /tmp/nodes_display_$$.txt | "$FZF_BIN" \
            --height=60% \
            --layout=reverse \
            --border \
            --header-lines=1 \
            --prompt="Select Node (ESC to go back) > " \
            --preview="echo 'Node: {}' && echo '' && kubectl get node \$(echo {} | awk '{print \$1}') -o wide 2>/dev/null" \
            --preview-window=down:8 \
            | awk '{print $1}') || true

          rm -f /tmp/nodes_$$.txt /tmp/nodes_display_$$.txt /tmp/nodes_headroom_$$.txt
          
          if [ -z "$selected_node" ]; then
            break  # ESC pressed
          fi
          
          # Enhanced actions menu for selected node
          while true; do
            local actions="1. Describe Node (Full Details) 📋
2. View Pods on This Node 🏃
3. Resource Usage (CPU/Memory) 📊
4. View Node Logs (Kubelet) 📜
5. Cordon Node (Prevent Scheduling) 🚫
6. Uncordon Node (Allow Scheduling) ✅
7. Drain Node (Evict Pods) 💧
8. View/Edit Labels 🏷️
9. View/Edit Taints 🚧
10. SSH into Node 💻
0. Back"
            
            local action
            action=$(echo "$actions" | "$FZF_BIN" \
              --height=50% \
              --layout=reverse \
              --border \
              --prompt="Manage $selected_node (ESC to go back) > " \
              --header="Node Management - Command Center") || true
            
            if [ -z "$action" ]; then
              break  # Go back to node list
            fi
            
            case "${action%%.*}" in
              1)
                clear
                echo -e "${BLUE}=== Node Description: $selected_node ===${NC}"
                run_kubectl "describe node $selected_node" | less
                ;;
              2)
                clear
                echo -e "${BLUE}=== Pods Running on $selected_node ===${NC}"
                echo ""
                run_kubectl "get pods -A --field-selector spec.nodeName=$selected_node -o wide"
                echo ""
                read -p "Press Enter to continue..."
                ;;
              3)
                clear
                echo -e "${BLUE}=== Resource Usage: $selected_node ===${NC}"
                echo ""
                echo -e "${YELLOW}CPU & Memory (actual usage):${NC}"
                run_kubectl "top node $selected_node" 2>/dev/null || echo "Metrics server not available"
                echo ""
                echo -e "${YELLOW}CPU Headroom (requests vs allocatable):${NC}"
                # Parse 'kubectl describe node' for pre-computed request %
                alloc_line=$(run_kubectl_silent "describe node $selected_node" | \
                    awk '/^Allocated resources:/,/^Events:/' | grep '^ *cpu ')
                req_raw=$(echo "$alloc_line"  | awk '{print $2}')
                req_pct=$(echo "$alloc_line"  | awk '{print $3}' | tr -d '(%)')
                alloc_raw=$(run_kubectl_silent "get node $selected_node -o jsonpath='{.status.allocatable.cpu}'")
                if [[ "$alloc_raw" == *m ]]; then alloc_m="${alloc_raw%m}"; else alloc_m=$(( ${alloc_raw:-1} * 1000 )); fi
                if [[ "$req_raw"   == *m ]]; then req_m="${req_raw%m}";     else req_m=$(( ${req_raw:-0} * 1000 )); fi
                headroom_m=$(( alloc_m - req_m ))
                pct="${req_pct:-$(( req_m * 100 / alloc_m ))}"
                if   (( pct >= 85 )); then color="${RED}";    icon="🔴"
                elif (( pct >= 75 )); then color="${YELLOW}"; icon="🟡"
                else                       color="${GREEN}";  icon="🟢"; fi
                echo -e "  ${icon} ${color}${req_m}m/${alloc_m}m requested (${pct}% used, ${headroom_m}m free)${NC}"
                echo -e "     Thresholds: 🟢 <75%  🟡 75–85%  🔴 >85%  (floor: ≥100m free)"
                echo ""
                echo -e "${YELLOW}Memory Allocatable:${NC}"
                run_kubectl "get node $selected_node -o jsonpath='{\"CPU: \"}{.status.allocatable.cpu}{\"  Memory: \"}{.status.allocatable.memory}{\"\\n\"}'"
                echo ""
                read -p "Press Enter to continue..."
                ;;
              4)
                clear
                echo -e "${BLUE}=== Node Logs (journalctl) ===${NC}"
                echo -e "${YELLOW}Note: This requires SSH access to the node${NC}"
                echo ""
                local ssh_target=$(echo "$selected_node" | sed 's/^k8s-/oci-k8s-/')
                [[ "$ssh_target" != oci-* ]] && ssh_target="oci-$ssh_target"
                ssh -t "$ssh_target" "sudo journalctl -u kubelet -n 100 --no-pager"
                read -p "Press Enter to continue..."
                ;;
              5)
                echo -e "${YELLOW}Cordoning $selected_node...${NC}"
                run_kubectl "cordon $selected_node"
                echo -e "${GREEN}✅ Node cordoned (no new pods will be scheduled)${NC}"
                read -p "Press Enter to continue..."
                ;;
              6)
                echo -e "${YELLOW}Uncordoning $selected_node...${NC}"
                if run_kubectl "uncordon $selected_node"; then
                    echo -e "${GREEN}✅ Node uncordoned (scheduling enabled)${NC}"
                    log_action "NODE" "Uncordon" "$selected_node"
                fi
                read -p "Press Enter to continue..."
                ;;
              7)
                echo -e "${RED}⚠️  WARNING: This will evict all pods from $selected_node${NC}"
                read -p "Type 'yes' to confirm: " confirm
                if [ "$confirm" = "yes" ]; then
                  echo -e "${YELLOW}Draining $selected_node...${NC}"
                  if run_kubectl "drain $selected_node --ignore-daemonsets --delete-emptydir-data --force --timeout=30s"; then
                    echo -e "${GREEN}✅ Node drained${NC}"
                    log_action "NODE" "Drain" "$selected_node"
                  fi
                else
                  echo "Cancelled."
                fi
                read -p "Press Enter to continue..."
                ;;
              8)
                clear
                echo -e "${BLUE}=== Labels on $selected_node ===${NC}"
                echo ""
                run_kubectl "get node $selected_node --show-labels"
                echo ""
                echo -e "${YELLOW}To add label: kubectl label node $selected_node key=value${NC}"
                echo -e "${YELLOW}To remove label: kubectl label node $selected_node key-${NC}"
                read -p "Press Enter to continue..."
                ;;
              9)
                clear
                echo -e "${BLUE}=== Taints on $selected_node ===${NC}"
                echo ""
                run_kubectl "get node $selected_node -o jsonpath='{.spec.taints}'" | jq '.' 2>/dev/null || echo "No taints"
                echo ""
                echo -e "${YELLOW}To add taint: kubectl taint node $selected_node key=value:NoSchedule${NC}"
                echo -e "${YELLOW}To remove taint: kubectl taint node $selected_node key:NoSchedule-${NC}"
                read -p "Press Enter to continue..."
                ;;
              10)
                clear
                echo -e "${BLUE}=== SSH into $selected_node ===${NC}"
                local ssh_target=$(echo "$selected_node" | sed 's/^k8s-/oci-k8s-/')
                [[ "$ssh_target" != oci-* ]] && ssh_target="oci-$ssh_target"
                echo -e "${YELLOW}Connecting to $ssh_target...${NC}"
                echo ""
                ssh -t "$ssh_target"
                ;;
              0)
                break
                ;;
            esac
          done
        done
        ;;
      12)
        clear
        ./safe_node_update.sh
        ;;
      13)
        cluster_maintenance_menu
        ;;
      14)
        security_menu # Now includes audit functionality
        ;;
      15)
        backup_menu
        ;;
      16)
        # Volume Manager (T-017)
        source scripts/volume_manager/tui_functions.sh
        manage_volumes
        ;;
      17)
        # Node Maintenance & Hardening
        node_maintenance_menu
        ;;
      18)
        # Kubecost
        source scripts/finops/kubecost_view.sh
        kubecost_menu
        ;;
      19)
        # DeepFlow
        source "$SCRIPT_DIR/scripts/observability/install_deepflow.sh"
        echo ""
        read -p "$(t "press_enter")"
        ;;
      20)
        # Uninstall DeepFlow
        source "$SCRIPT_DIR/scripts/observability/uninstall_deepflow.sh"
        echo ""
        read -p "$(t "press_enter")"
        ;;
      21)
        # Install Pixie
        source "$SCRIPT_DIR/scripts/observability/install_pixie.sh"
        echo ""
        read -p "$(t "press_enter")"
        ;;
      22)
        # Uninstall Pixie
        source "$SCRIPT_DIR/scripts/observability/uninstall_pixie.sh"
        echo ""
        read -p "$(t "press_enter")"
        ;;
      23)
        # Install Coroot
        source "$SCRIPT_DIR/scripts/observability/install_coroot.sh"
        install_coroot
        echo ""
        read -p "$(t "press_enter")"
        ;;
      24)
        # Uninstall Coroot
        source "$SCRIPT_DIR/scripts/observability/uninstall_coroot.sh"
        uninstall_coroot
        echo ""
        read -p "$(t "press_enter")"
        ;;
      25)
        # Install Parca
        source "$SCRIPT_DIR/scripts/observability/install_parca.sh"
        install_parca
        echo ""
        read -p "$(t "press_enter")"
        ;;
      26)
        # Uninstall Parca
        source "$SCRIPT_DIR/scripts/observability/uninstall_parca.sh"
        uninstall_parca
        echo ""
        read -p "$(t "press_enter")"
        ;;
      27)
        # Cloud Rescue
        source "$SCRIPT_DIR/lib/oci_wrapper.sh"
        source "$SCRIPT_DIR/scripts/cloud_ops/tui_cloud.sh"
        cloud_ops_menu
        ;;
      28)
        preferences_menu
        ;;
      29)
        # Cluster Health Report (T-102)
        clear
        echo -e "${BLUE}Running health check on master node...${NC}"
        ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            "$MASTER_NODE" \
            "bash /opt/k8s-ops/cluster_health_check.sh 2>/dev/null || \
             bash ~/cluster_health_check.sh 2>/dev/null || \
             echo '⚠️  cluster_health_check.sh not installed on master. Run: scripts/observability/install_health_watchdog.sh'" \
            || true
        echo ""
        read -p "$(t 'press_enter')"
        ;;
      30)
        catalog_menu
        ;;
      31)
        jslibs_menu
        ;;
      32)
        # Cluster Bootstrap — k3s on any cloud machine (T-295)
        source "$SCRIPT_DIR/scripts/bootstrap/tui_bootstrap.sh"
        bootstrap_cluster_menu
        ;;

      0)
        echo "Bye!"
        exit 0
        ;;
    esac
  done
}

# ==============================================================================
# 📚 Inventory & Catalog Menu (T-110)
# ==============================================================================
catalog_menu() {
    local catalog_script="$SCRIPT_DIR/scripts/observability/generate_catalog.sh"
    local report_root
    report_root="$(cd "$SCRIPT_DIR/.." && pwd)/reports"
    local latest_link="$report_root/latest-catalog"
    local catalog_json="$latest_link/catalog.json"

    while true; do
        local stale_msg=""
        if [ -f "$catalog_json" ]; then
            local age=$(( $(date +%s) - $(stat -c %Y "$catalog_json" 2>/dev/null || echo 0) ))
            if [ $age -gt 86400 ]; then
                stale_msg=" ⚠️ (stale: $(( age / 3600 ))h ago)"
            else
                stale_msg=" ✅ ($(( age / 60 ))min ago)"
            fi
        else
            stale_msg=" ❌ (no catalog yet)"
        fi

        local actions="$(t "cat_view_apps")
$(t "cat_view_components")
$(t "cat_cross_ref")
$(t "cat_generate")
$(t "cat_open_html")
$(t "prefs_back")"

        local selected_action
        selected_action=$(echo "$actions" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="$(t 'cat_menu_title')${stale_msg} > ") || true

        if [ -z "$selected_action" ]; then
            return
        fi

        case "${selected_action%%.*}" in
            1)
                # View Apps Catalog
                clear
                if [ ! -f "$catalog_json" ]; then
                    echo -e "${YELLOW}No catalog found. Generating...${NC}"
                    bash "$catalog_script"
                    catalog_json="$latest_link/catalog.json"
                fi
                echo -e "${BOLD}${BLUE}📦 Applications Catalog${NC}"
                echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"
                jq -r '.apps[] |
                    "\(.name)" + "\t" +
                    "\(.language)" + "\t" +
                    "\(.framework // "-")" + "\t" +
                    "\(.version // "-")" + "\t" +
                    (if .dockerfile then "✅" else "❌" end) + "\t" +
                    (if .k8s_manifests then "✅" else "❌" end) + "\t" +
                    (if .deploy_readiness == "ready" then "🟢 Ready"
                     elif .deploy_readiness == "partial" then "🟡 Partial"
                     else "🔴 None" end)
                ' "$catalog_json" | column -t -s $'\t' -N "APP,LANG,FRAMEWORK,VERSION,DOCKER,K8S,READINESS"
                echo ""
                read -p "$(t 'press_enter')"
                ;;
            2)
                # View Components Catalog
                clear
                if [ ! -f "$catalog_json" ]; then
                    echo -e "${YELLOW}No catalog found. Generating...${NC}"
                    bash "$catalog_script"
                    catalog_json="$latest_link/catalog.json"
                fi
                echo -e "${BOLD}${BLUE}⚙️  Components Catalog${NC}"
                echo -e "${BLUE}$(printf '─%.0s' {1..80})${NC}"
                jq -r '.components[] |
                    "\(.name)" + "\t" +
                    "\(.category)" + "\t" +
                    "\(.namespace // "-")" + "\t" +
                    "\(.version // "-")" + "\t" +
                    "\(.deploy_method)" + "\t" +
                    (if .has_commands_sh then "✅" else "❌" end) + "\t" +
                    (if .has_readme then "✅" else "❌" end) + "\t" +
                    (if .deprecated then "🗑️" else "-" end)
                ' "$catalog_json" | column -t -s $'\t' -N "COMPONENT,CATEGORY,NAMESPACE,VERSION,METHOD,CMDS,DOCS,DEPR"
                echo ""
                read -p "$(t 'press_enter')"
                ;;
            3)
                # Cross-Reference
                clear
                if [ ! -f "$catalog_json" ]; then
                    echo -e "${YELLOW}No catalog found. Generating...${NC}"
                    bash "$catalog_script"
                    catalog_json="$latest_link/catalog.json"
                fi
                echo -e "${BOLD}${BLUE}🔄 Cross-Reference: Repo ↔ Cluster${NC}"
                echo -e "${BLUE}$(printf '─%.0s' {1..70})${NC}"

                local online=$(jq -r '.cluster_online' "$catalog_json")
                if [ "$online" != "true" ]; then
                    echo -e "${YELLOW}⚠️  Cluster was offline when catalog was generated. Re-generate with tunnel active.${NC}"
                    echo ""
                fi

                echo -e "${GREEN}${BOLD}✅ Deployed & Tracked:${NC}"
                jq -r '.cross_reference.deployed_tracked[] |
                    "  " + (if .status == "healthy" then "🟢" else "⚠️" end) +
                    " \(.name) (\(.source)) → \(.cluster_workloads | join(", "))"
                ' "$catalog_json"
                echo ""

                echo -e "${YELLOW}${BOLD}📦 Repo-Only (Not Deployed):${NC}"
                jq -r '.cross_reference.repo_only.apps[] |
                    "  📦 \(.name) (\(.language), \(.readiness))"
                ' "$catalog_json"
                jq -r '.cross_reference.repo_only.components[] |
                    "  📦 \(.name) (\(.category))"
                ' "$catalog_json"
                echo ""

                local co=$(jq '.cross_reference.cluster_only | length' "$catalog_json")
                if [ "$co" -gt 0 ]; then
                    echo -e "${RED}${BOLD}🔴 Cluster-Only (Untracked):${NC}"
                    jq -r '.cross_reference.cluster_only[] |
                        "  🔴 \(.name) (\(.kind), \(.namespace))"
                    ' "$catalog_json"
                    echo ""
                fi

                echo -e "${YELLOW}${BOLD}📊 Gap Analysis:${NC}"
                local nd=$(jq '.cross_reference.gaps.no_docs | length' "$catalog_json")
                local ns=$(jq '.cross_reference.gaps.no_deploy_script | length' "$catalog_json")
                local nf=$(jq '.cross_reference.gaps.no_dockerfile | length' "$catalog_json")
                local nc=$(jq '.cross_reference.gaps.no_commands_sh | length' "$catalog_json")
                echo -e "  📝 Missing docs: $nd  |  🔧 Missing deploy: $ns  |  🐳 Missing Dockerfile: $nf  |  ⚙️ Missing commands.sh: $nc"
                echo ""
                read -p "$(t 'press_enter')"
                ;;
            4)
                # Generate Full Report
                clear
                bash "$catalog_script"
                catalog_json="$latest_link/catalog.json"
                echo ""
                read -p "$(t 'press_enter')"
                ;;
            5)
                # Open HTML in browser
                local html="$latest_link/catalog.html"
                if [ ! -f "$html" ]; then
                    echo -e "${YELLOW}No HTML report found. Generate first (option 4).${NC}"
                    read -p "$(t 'press_enter')"
                    continue
                fi
                if command -v explorer.exe &>/dev/null; then
                    explorer.exe "$(wslpath -w "$html")" 2>/dev/null &
                elif command -v xdg-open &>/dev/null; then
                    xdg-open "$html" 2>/dev/null &
                else
                    echo -e "${BLUE}Open: file://$html${NC}"
                fi
                echo -e "${GREEN}✅ Opened in browser${NC}"
                sleep 1
                ;;
            0)
                return
                ;;
        esac
    done
}

# Start
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_menu
fi
