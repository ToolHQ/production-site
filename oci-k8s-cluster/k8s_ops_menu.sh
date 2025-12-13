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

# State variables
CURRENT_NS="default"
CURRENT_POD=""
FZF_BIN="/tmp/k8s_ops_fzf"

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
      -q "$MASTER_NODE" "kubectl $cmd"
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
  
  # Helper for clean capture
  capture_clean() {
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -q "$MASTER_NODE" "$1" 2>/dev/null
  }
  
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
      0)
        return
        ;;
    esac
  done
}

component_management_menu() {
  while true; do
    local actions="$(t "comp_deploy")
$(t "comp_longhorn")
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
        ./reinstall_longhorn.sh
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
    local lsof_output=$(sudo lsof -i -P -n 2>/dev/null | grep -E '^ssh.*LISTEN')
    
    if [ -z "$lsof_output" ]; then
        return 1
    fi
    
    # Parse lsof output to get PID and port
    # Column 2: PID, Column 9: NAME (e.g., "127.0.0.1:8443" or "[::1]:8443")
    local tunnel_info=$(echo "$lsof_output" | awk '{
        # Extract port from NAME column (format: IP:PORT or [IP]:PORT)
        if (match($9, /:([0-9]+)/, arr)) {
            port = arr[1]
            # Skip port 1 (SSH multiplexing control socket)
            if (port != "1") {
                print $2, port
            }
        }
    }' | sort -u)
    
    if [ -z "$tunnel_info" ]; then
        return 1
    fi
    
    # Enrich with metadata
    while read -r pid local_port; do
        [ -z "$pid" ] && continue
        
        local meta_file="$TUNNEL_DIR/$local_port.meta"
        local service_info="Unknown Service"
        local namespace="unknown"
        
        if [ -f "$meta_file" ]; then
            service_info=$(cat "$meta_file" | cut -d'|' -f1)
            namespace=$(cat "$meta_file" | cut -d'|' -f2)
            local protocol=$(cat "$meta_file" | cut -d'|' -f4 2>/dev/null || echo "unknown")
            # Append protocol to service_info for display
            if [ -n "$protocol" ] && [ "$protocol" != "unknown" ]; then
                service_info="$service_info [$protocol]"
            fi
        fi
        
        # Get remote port from process cmdline
        # Handle both formats: 127.0.0.1:PORT and IP:PORT
        local cmdline=$(ps -p "$pid" -o args= 2>/dev/null)
        local remote_port="unknown"
        
        # Try to extract port from -L argument (format: localport:host:remoteport)
        if [[ "$cmdline" =~ -L[[:space:]]+([0-9]+):([^:]+):([0-9]+) ]]; then
            remote_port="${BASH_REMATCH[3]}"
        elif [[ "$cmdline" =~ 127\.0\.0\.1:([0-9]+) ]]; then
            remote_port="${BASH_REMATCH[1]}"
        fi
        
        echo "$pid|$service_info|$namespace|$local_port|$remote_port"
    done <<< "$tunnel_info"
}

start_tunnel() {
    local target_ns="${1:-}"
    local target_svc="${2:-}"
    local target_local_port="${3:-}"
    local target_remote_port="${4:-}"
    local target_desc="${5:-}"
    local force_port="${6:-false}"  # New parameter: force use of specific port

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
        
        # Check and kill if in use
        # We use sudo lsof because the process binding a privileged port is likely root
        if sudo lsof -i ":$local_port" > /dev/null 2>&1; then
             echo -e "${YELLOW}Port $local_port is busy. Killing occupant...${NC}"
             local pids=$(sudo lsof -t -iTCP:"$local_port" -sTCP:LISTEN)
             if [ -n "$pids" ]; then
                 # Kill each PID individually (in case there are multiple)
                 for pid in $pids; do
                     sudo kill "$pid" 2>/dev/null || true
                 done
             fi
        fi
    else
        echo -e "${BLUE}Finding available local port (base: $desired_port)...${NC}"
        local_port=$(find_available_port "$desired_port" "$allow_priv")
        
        if [ "$local_port" != "$desired_port" ]; then
            echo -e "${YELLOW}Port $desired_port in use, using $local_port instead.${NC}"
        fi
    fi

    echo -e "${BLUE}Starting background tunnel for $svc_info ($local_port -> $remote_port)...${NC}"
    
    # Check if we need sudo for privileged ports
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
        
        $use_sudo ssh $ssh_config_opt -i "$SSH_KEY" -f -N -L "$local_port:127.0.0.1:$remote_port" \
            -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ExitOnForwardFailure=yes \
            "$MASTER_NODE"
    else
        ssh -f -N -L "$local_port:127.0.0.1:$remote_port" \
            -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ExitOnForwardFailure=yes \
            "$MASTER_NODE"
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Tunnel started!${NC}"
        
        # Robust protocol detection with actual connectivity test
        local detected_protocol="tcp"
        echo -n "Detecting protocol... "
        sleep 1
        
        # Check if it's likely HTTPS (port 443, 8443, or service name contains 'dashboard', 'kong', 'ssl', 'tls')
        if [[ "$local_port" =~ ^(443|8443)$ ]] || [[ "$remote_port" =~ ^(443|31271)$ ]] || \
           [[ "$service_name" =~ (dashboard|kong|ssl|tls|secure) ]]; then
            # Test HTTPS first
            if curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "https://localhost:$local_port" >/dev/null 2>&1; then
                detected_protocol="https"
                echo -e "${GREEN}HTTPS${NC}"
            elif curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:$local_port" >/dev/null 2>&1; then
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
            if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:$local_port" >/dev/null 2>&1; then
                detected_protocol="http"
                echo -e "${GREEN}HTTP${NC}"
            elif curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "https://localhost:$local_port" >/dev/null 2>&1; then
                detected_protocol="https"
                echo -e "${YELLOW}HTTPS (expected HTTP)${NC}"
            else
                detected_protocol="tcp"
                echo -e "${GRAY}TCP (no HTTP/HTTPS)${NC}"
            fi
        # Default: TCP check for databases and other services
        else
            if nc -z localhost "$local_port" >/dev/null 2>&1; then
                detected_protocol="tcp"
                echo -e "${GREEN}TCP${NC}"
            else
                detected_protocol="unknown"
                echo -e "${RED}No response${NC}"
            fi
        fi
        
        # Save metadata with detected protocol
        echo "$svc_info|$namespace|$service_name|$detected_protocol" > "$TUNNEL_DIR/$local_port.meta"
        
        # Display access URL with correct protocol
        if [ "$detected_protocol" = "https" ]; then
            echo -e "Access URL: ${YELLOW}https://localhost:$local_port${NC}"
        elif [ "$detected_protocol" = "http" ]; then
            echo -e "Access URL: ${YELLOW}http://localhost:$local_port${NC}"
        else
            echo -e "Access URL: ${YELLOW}localhost:$local_port${NC} (protocol: $detected_protocol)"
        fi
    else
        echo -e "${RED}Failed to start tunnel.${NC}"
    fi
    read -p "Press Enter to continue..."
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
    echo "$(t "ingress_detecting")" >&2
    # Try to find ingress-nginx-controller service in all namespaces
    local raw_data
    raw_data=$(run_kubectl "get svc -A -o jsonpath='{range .items[*]}{@.metadata.namespace}{\"|\"}{@.metadata.name}{\"|\"}{range @.spec.ports[*]}{.name}{\":\"}{.nodePort}{\",\"}{end}{\"\\n\"}{end}'")
    
    local ingress_svc
    ingress_svc=$(parse_ingress_data "$raw_data")
    
    if [ -z "$ingress_svc" ]; then
        echo "$(t "ingress_not_found")" >&2
        return 1
    fi
    
    echo "$ingress_svc"
}

get_ingress_hosts() {
    run_kubectl "get ingress -A -o jsonpath='{range .items[*]}{@.spec.rules[*].host}{\" \"}{end}'" | tr ' ' '\n' | sort | uniq | grep -v "^$"
}

ingress_menu() {
    while true; do
        clear
        echo -e "${BLUE}=== $(t "ingress_menu_title") ===${NC}"
        echo ""
        
        # Detect controller
        local ingress_info
        ingress_info=$(detect_ingress_controller)
        local status_icon="❌"
        
        if [ $? -eq 0 ]; then
            status_icon="✅"
            # Parse info: namespace|name|http:32xxx,https:32xxx,
            local ns=$(echo "$ingress_info" | cut -d'|' -f1)
            local name=$(echo "$ingress_info" | cut -d'|' -f2)
            local ports=$(echo "$ingress_info" | cut -d'|' -f3)
            
            echo -e "Controller: ${GREEN}$name${NC} ($ns)"
            echo -e "Ports: ${YELLOW}$ports${NC}"
        else
            echo -e "${RED}$(t "ingress_not_found")${NC}"
        fi
        
        echo ""
        echo "$(t "ingress_start_tunnel")"
        echo "$(t "ingress_show_dns")"
        echo "$(t "prefs_back")"
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
                    start_tunnel "$ns" "$name" "80" "$http_port" "Ingress HTTP" "true"
                fi
                if [ -n "$https_port" ]; then
                    start_tunnel "$ns" "$name" "443" "$https_port" "Ingress HTTPS" "true"
                fi
                
                # Also create TCP tunnel for PostgreSQL if port is exposed
                if [ -n "$postgres_port" ]; then
                    echo -e "${BLUE}Creating PostgreSQL TCP tunnel (local 5432 → remote $postgres_port)...${NC}"
                    start_tunnel "$ns" "$name" "5432" "$postgres_port" "PostgreSQL TCP" "true"
                else
                    echo -e "${YELLOW}PostgreSQL TCP port not found in Ingress Controller service${NC}"
                fi
                
                echo -e "${GREEN}$(t "ingress_tunnel_running")${NC}"
                read -p "$(t "press_enter")"
                ;;
            2)
                update_hosts_file
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
    local hosts
    hosts=$(run_kubectl "get ingress -A -o jsonpath='{.items[*].spec.rules[*].host}'" | tr ' ' '\n' | sort -u | grep -v "^$")
    
    if [ -z "$hosts" ]; then
        echo -e "${YELLOW}No Ingress hosts found.${NC}"
        read -p "Press Enter..."
        return
    fi

    echo -e "Found hosts:\n$hosts"
    echo ""
    echo -e "${YELLOW}This will add the above hosts to your local /etc/hosts pointing to 127.0.0.1.${NC}"
    echo -e "${YELLOW}Root privileges (sudo) are required.${NC}"
    read -p "Do you want to proceed? (y/N) " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        local entries=""
        for host in $hosts; do
            entries+="127.0.0.1 $host\n"
        done
        
        # Create a temporary file with the new entries
        local tmp_file=$(mktemp)
        echo -e "\n# Kubernetes Ingress Tunnels (dnor.io)" > "$tmp_file"
        echo -e "$entries" >> "$tmp_file"
        
        echo -e "${BLUE}Updating /etc/hosts...${NC}"
        
        # Use sudo to append to /etc/hosts if not already present
        # This is a simple append strategy. For more complex management, we'd need sed/awk.
        # We first check if the marker exists to avoid duplication block
        if grep -q "# Kubernetes Ingress Tunnels (dnor.io)" /etc/hosts; then
             echo -e "${YELLOW}Entries might already exist. Appending new block anyway...${NC}"
             sudo bash -c "cat '$tmp_file' >> /etc/hosts"
        else
             sudo bash -c "cat '$tmp_file' >> /etc/hosts"
        fi
        
        rm "$tmp_file"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Successfully updated /etc/hosts!${NC}"
            
            # Check for WSL to update Windows hosts
            if grep -qEi "(Microsoft|WSL)" /proc/version; then
                echo ""
                echo -e "${BLUE}WSL Detected!${NC}"
                echo -e "${YELLOW}Do you want to update Windows hosts file as well?${NC}"
                echo -e "${GRAY}(This will open a UAC prompt for PowerShell)${NC}"
                read -p "Update Windows hosts? (y/N) " update_win
                
                if [[ "$update_win" =~ ^[Yy]$ ]]; then
                    # Prepare PowerShell script to append hosts
                    # We use a temporary PS1 script to avoid complex escaping in the command line
                    local win_hosts_path="C:\Windows\System32\drivers\etc\hosts"
                    local ps_script="
\$hostsPath = '$win_hosts_path'
\$entries = @(
$(for host in $hosts; do echo "    '127.0.0.1 $host'"; done)
)

\$currentContent = Get-Content \$hostsPath -Raw
\$newContent = \"\`r\`n# Kubernetes Ingress Tunnels (dnor.io)\`r\`n\"
\$needsUpdate = \$false

foreach (\$entry in \$entries) {
    if (\$currentContent -notmatch [regex]::Escape(\$entry)) {
        \$newContent += \"\$entry\`r\`n\"
        \$needsUpdate = \$true
    }
}

if (\$needsUpdate) {
    Add-Content -Path \$hostsPath -Value \$newContent
    Write-Host 'Windows hosts file updated!' -ForegroundColor Green
} else {
    Write-Host 'Entries already exist.' -ForegroundColor Yellow
}
Start-Sleep -Seconds 3
"
                    # Save PS script to a temp file accessible by Windows (current dir is likely mounted)
                    # Use /tmp but ensure it's convertible to Windows path, or just use current dir if safe.
                    # Safest is to pass the command encoded or just simple append.
                    # Let's try a simpler append approach via Start-Process to avoid file sharing issues.
                    # Actually, passing a complex script block to Start-Process is tricky.
                    # Let's write the script to a temp file in the current directory (which is shared)
                    echo "$ps_script" > "update_win_hosts.ps1"
                    
                    # Convert linux path to windows path (mixed mode / for safety in bash strings)
                    local win_script_path
                    if command -v wslpath >/dev/null; then
                        win_script_path=$(wslpath -m "./update_win_hosts.ps1")
                    else
                        # Fallback simple conversion (hope for no backslash issues)
                        win_script_path=".\\update_win_hosts.ps1"
                    fi
                    
                    echo -e "${BLUE}Launching PowerShell as Admin...${NC}"
                    # Use -Command and single quotes for inner args to handle parsing correctly
                    # Use -Wait to ensure script finishes before we delete the file
                    powershell.exe -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-ExecutionPolicy Bypass -File \"$win_script_path\"'"
                    
                    echo -e "${GREEN}Windows hosts update completed.${NC}"
                    rm "update_win_hosts.ps1"
                fi
            fi
        else
            echo -e "${RED}Failed to update /etc/hosts.${NC}"
        fi
    else
        echo "Cancelled."
    fi
    
    read -p "Press Enter..."
}


manage_tunnels() {
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
        menu_items="← Return to Main Menu\n"
        
        while IFS='|' read -r pid svc_info namespace local_port remote_port; do
            menu_items+="$svc_info (Local: $local_port -> Remote: $remote_port) [PID: $pid]\n"
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
        fi

        local pid_to_kill=$(echo "$selected" | grep -oP 'PID: \K[0-9]+')
        local lport_to_kill=$(echo "$selected" | grep -oP 'Local: \K[0-9]+')
        
        if [ -n "$pid_to_kill" ]; then
            kill "$pid_to_kill" 2>/dev/null
            [ -f "$TUNNEL_DIR/$lport_to_kill.meta" ] && rm "$TUNNEL_DIR/$lport_to_kill.meta"
            echo -e "${RED}Tunnel stopped (PID: $pid_to_kill, Port: $lport_to_kill).${NC}"
            sleep 0.5
        fi
    done
}

# --- SECURITY MENU ---
security_menu() {
    while true; do
        local menu="$(t "sec_check_certs")
$(t "sec_view_policies")
$(t "sec_force_renew")
$(t "sec_export_ca")
$(t "sec_install_ca")
$(t "back")"

        local selected
        selected=$(echo "$menu" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Security > " --header="$(t "sec_menu_title")") || true

        if [ -z "$selected" ]; then
            return
        fi

        case "${selected%%.*}" in
            1)
                echo -e "${BLUE}📜 Certificates:${NC}"
                run_kubectl "get certificate -A"
                echo ""
                echo -e "${BLUE}📜 Certificate Requests:${NC}"
                run_kubectl "get certificaterequest -A"
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
            4)
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
                    # Extract CA cert from secret
                    run_remote_raw "$MASTER_NODE" "kubectl -n cert-manager get secret $secret_name -o jsonpath='{.data.ca\.crt}' | base64 -d" > "${selected_issuer}.crt"
                    
                    echo -e "${GREEN}✅ Certificate saved to: $(pwd)/${selected_issuer}.crt${NC}"
                    echo ""
                    echo -e "${YELLOW}👉 How to Import:${NC}"
                    echo "1. Copy '${selected_issuer}.crt' to your local machine."
                    echo "2. Windows: Double-click > Install Certificate > Local Machine > Place in 'Trusted Root Certification Authorities'."
                    echo "3. Chrome: Settings > Privacy and security > Security > Manage certificates > Authorities > Import."
                    echo "4. Linux: Copy to /usr/local/share/ca-certificates/ and run 'update-ca-certificates'."
                else
                    echo -e "${RED}❌ Secret '$secret_name' not found.${NC}"
                fi
                read -p "$(t "press_enter")"
                ;;
            5)
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
                     echo -e "${YELLOW}No local .crt files found. Please use Option 4 to export one first.${NC}"
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
0. Back"
        
        local choice
        choice=$(echo "$actions" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Backup Ops (ESC to go back) > " --header="Backup & Disaster Recovery") || true
        
        if [ -z "$choice" ]; then
            break  # ESC pressed, go back
        fi
        
        case "${choice%%.*}" in
            1)
                echo -e "${BLUE}📊 Checking Backup Status...${NC}"
                echo -e "${YELLOW}--- Etcd Backups ---${NC}"
                run_kubectl "get cronjob etcd-backup -n kube-system"
                echo ""
                echo -e "${YELLOW}--- Longhorn Backups ---${NC}"
                run_kubectl "get recurringjob -n longhorn-system"
                read -p "$(t "press_enter")"
                ;;
            2)
                echo -e "${BLUE}💾 Triggering Manual Etcd Backup...${NC}"
                run_kubectl "create job --from=cronjob/etcd-backup etcd-backup-manual-$(date +%s) -n kube-system"
                echo -e "${GREEN}✅ Backup job created.${NC}"
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
$(t "ingress_menu_title")
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
      3) ingress_menu ;;
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
        
        while IFS='|' read -r pid svc_info namespace local_port remote_port; do
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
            
            # Build URL if http/https
            local url_info=""
            if [[ "$protocol" == "http" ]] || [[ "$protocol" == "https" ]]; then
                url_info=" → ${protocol}://localhost:${local_port}"
            else
                url_info=" [$protocol]"
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
    
    # Iterate through configured ports
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

# --- TUNNEL MANAGEMENT ---

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
$(t "menu_dashboard")
$(printf "$(t "menu_namespace")" "$CURRENT_NS")
$(t "menu_pod")
$(t "menu_all_pods")
$(t "menu_nodes")
$(t "menu_update")
$(t "menu_maintenance")
$(t "menu_preferences")
$(t "menu_security")
$(t "menu_backup")
$(t "menu_volumes")
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
        open_dashboard
        ;;
      7)
        select_namespace
        ;;
      8)
        select_pod
        ;;
      9)
        clear
        run_kubectl "get pods -A -o wide" | less -S
        ;;
      10)
        # Node Status - Interactive Menu with fzf
        while true; do
          echo -e "${BLUE}📊 Node Status${NC}"
          echo ""
          
          # Build formatted table for fzf
          local node_data=""
          local header="NODE|STATUS||CONDITION|ROLE|VERSION|AGE"
          
          run_kubectl "get nodes --no-headers" | while read name status roles age version rest; do
            local status_icon="❌"
            if [ "$status" = "Ready" ]; then
              status_icon="✅"
              status="Ready"
            fi
            
            if [ "$roles" = "<none>" ]; then
              roles="worker"
            fi
            
            echo "$name|$status_icon|$status|$roles|$version|$age"
          done > /tmp/nodes_$$.txt
          
          
          # Create formatted display with proper spacing
          {
            printf "%-20s %-8s %-10s %-15s %-12s %-6s\n" "NODE" "STATUS" "CONDITION" "ROLE" "VERSION" "AGE"
            while IFS='|' read -r name icon status role version age; do
              printf "%-20s %-8s %-10s %-15s %-12s %-6s\n" "$name" "$icon" "$status" "$role" "$version" "$age"
            done < /tmp/nodes_$$.txt
          } > /tmp/nodes_display_$$.txt
          
          
          # Use fzf with working preview (no SSH complications)
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
          
          rm -f /tmp/nodes_$$.txt /tmp/nodes_display_$$.txt
          
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
                echo -e "${YELLOW}CPU & Memory:${NC}"
                run_kubectl "top node $selected_node" 2>/dev/null || echo "Metrics server not available"
                echo ""
                echo -e "${YELLOW}Capacity:${NC}"
                run_kubectl "get node $selected_node -o jsonpath='{\"CPU: \"}{.status.capacity.cpu}{\" Memory: \"}{.status.capacity.memory}{\"\\n\"}'"
                echo ""
                echo -e "${YELLOW}Allocatable:${NC}"
                run_kubectl "get node $selected_node -o jsonpath='{\"CPU: \"}{.status.allocatable.cpu}{\" Memory: \"}{.status.allocatable.memory}{\"\\n\"}'"
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
                run_kubectl "uncordon $selected_node"
                echo -e "${GREEN}✅ Node uncordoned (scheduling enabled)${NC}"
                read -p "Press Enter to continue..."
                ;;
              7)
                echo -e "${RED}⚠️  WARNING: This will evict all pods from $selected_node${NC}"
                read -p "Type 'yes' to confirm: " confirm
                if [ "$confirm" = "yes" ]; then
                  echo -e "${YELLOW}Draining $selected_node...${NC}"
                  run_kubectl "drain $selected_node --ignore-daemonsets --delete-emptydir-data"
                  echo -e "${GREEN}✅ Node drained${NC}"
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
      11)
        clear
        ./safe_node_update.sh
        ;;
      12)
        cluster_maintenance_menu
        ;;
      13)
        preferences_menu
        ;;
      14)
        security_menu
        ;;
      15)
        backup_menu
        ;;
      16)
        # Volume Manager (T-017)
        source scripts/volume_manager/tui_functions.sh
        manage_volumes
        ;;
      0)
        echo "Bye!"
        exit 0
        ;;
    esac
  done
}

# Start
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main_menu
fi
