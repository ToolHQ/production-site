#!/usr/bin/env bash
set -euo pipefail

# Source common configuration for SSH keys and node info
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/lib/credstore.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
  token=$(capture_clean "kubectl -n kubernetes-dashboard create token admin-user --duration=24h 2>/dev/null")
  
  if [ -z "$token" ]; then
    echo -e "${RED}Failed to get token. Is dashboard installed?${NC}"
    read -p "Press Enter..."
    return
  fi
  
  # 2. Get ClusterIP for Dashboard
  echo "Resolving Dashboard IP..."
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
  local local_port=$(find_available_port 8443)
  
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
  
  # Save metadata
  echo "kubernetes-dashboard/kubernetes-dashboard-kong-proxy|kubernetes-dashboard|dashboard" > "$TUNNEL_DIR/$local_port.meta"
  
  # 5. Wait for tunnel
  echo "Waiting for tunnel to establish..."
  local retries=0
  while ! nc -z localhost "$local_port" >/dev/null 2>&1; do
    sleep 1
    ((retries++))
    if [ $retries -gt 10 ]; then
      echo -e "${RED}Timeout waiting for tunnel.${NC}"
      read -p "Press Enter..."
      return
    fi
  done
  
  local url="https://localhost:$local_port/#/workloads?namespace=_all"
  
  # 6. Display and Open
  echo -e "\n${GREEN}Token (Copied to clipboard if possible):${NC}"
  echo "$token"
  echo -e "\n${YELLOW}URL:${NC} $url"
  
  # Try to copy to clipboard (Linux/Mac/WSL)
  if command -v clip.exe >/dev/null 2>&1; then
    # WSL Clipboard
    echo -n "$token" | clip.exe
    echo -e "${GREEN}(Token copied to clipboard via clip.exe)${NC}"
  elif command -v xclip >/dev/null 2>&1; then
    echo -n "$token" | xclip -selection clipboard
    echo -e "${GREEN}(Token copied to clipboard)${NC}"
  elif command -v pbcopy >/dev/null 2>&1; then
    echo -n "$token" | pbcopy
    echo -e "${GREEN}(Token copied to clipboard)${NC}"
  else
    echo -e "${YELLOW}(Clipboard tool not found - please copy token manually)${NC}"
  fi
  
  echo -e "\n${BLUE}Opening browser...${NC}"
  open_url "$url"
  
  echo -e "\n${GREEN}Dashboard tunnel running in background on port $local_port${NC}"
  echo -e "${GRAY}You can manage this tunnel via 'Access & Port Forwarding' -> 'Manage Active Tunnels'${NC}"
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
  selected=$(echo "$ns_list" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Select Namespace > " --header="Current: $CURRENT_NS")
  
  if [ -n "$selected" ]; then
    CURRENT_NS="$selected"
  fi
}

select_pod() {
  echo "Fetching pods in $CURRENT_NS..."
  local pod_list
  pod_list=$(run_kubectl "-n $CURRENT_NS get pods --no-headers -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp")
  
  if [ -z "$pod_list" ]; then
    echo -e "${YELLOW}No pods found in namespace $CURRENT_NS.${NC}"
    read -p "Press Enter to continue..."
    return
  fi

  local selected_line
  selected_line=$(echo "$pod_list" | "$FZF_BIN" --height=40% --layout=reverse --border --header-lines=0 --prompt="Select Pod > " --header="Namespace: $CURRENT_NS")
  
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
    selected_action=$(echo "$actions" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Action for $CURRENT_POD > ")

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
    local actions="1. Full Cluster Setup/Repair (setup_k8s_cluster.sh) 🏗️
2. Full Cluster Heal (Nuclear Option) ☢️
3. Fix IPTables (Open Ports) 🔥
4. Fix DNS (CoreDNS/Cilium) 🧪
5. Fix Host Network (OS/Resolv.conf) 🛠️
0. Back"

    local selected_action
    selected_action=$(echo "$actions" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Maintenance > ")

    if [ -z "$selected_action" ]; then
      return
    fi

    case "${selected_action%%.*}" in
      1)
        clear
        echo -e "${BLUE}Running Full Cluster Setup/Repair...${NC}"
        ./setup_k8s_cluster.sh
        read -p "Press Enter to continue..."
        ;;
      2)
        clear
        echo -e "${RED}Running Full Cluster Heal (Nuclear)...${NC}"
        ./full_cluster_heal.sh
        read -p "Press Enter to continue..."
        ;;
      3)
        clear
        ./fix_iptables.sh
        read -p "Press Enter to continue..."
        ;;
      4)
        clear
        ./dns_doctor.sh
        read -p "Press Enter to continue..."
        ;;
      5)
        clear
        ./os_network_doctor.sh
        read -p "Press Enter to continue..."
        ;;
      0)
        return
        ;;
    esac
  done
}

component_management_menu() {
  while true; do
    local actions="1. Deploy/Update Components (Interactive) 📦
2. Reinstall Longhorn (Storage) 💾
0. Back"

    local selected_action
    selected_action=$(echo "$actions" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Components > ")

    if [ -z "$selected_action" ]; then
      return
    fi

    case "${selected_action%%.*}" in
      1)
        clear
        ./deploy_components.sh
        read -p "Press Enter to continue..."
        ;;
      2)
        clear
        ./reinstall_longhorn.sh
        read -p "Press Enter to continue..."
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
    local port=$base_port
    local max_attempts=100
    
    # For privileged ports (<1024), use mnemonic offset: 8000 + port
    if [ $port -lt 1024 ]; then
        port=$((8000 + base_port))
        echo -e "${YELLOW}Note: Port $base_port requires root. Trying $port (8000+$base_port)...${NC}" >&2
    fi
    
    for ((i=0; i<max_attempts; i++)); do
        # Skip privileged ports during iteration
        if [ $port -lt 1024 ]; then
            ((port++))
            continue
        fi
        
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
    local lsof_output=$(lsof -i -P -n 2>/dev/null | grep -E '^ssh.*LISTEN')
    
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
        local cmdline=$(ps -p "$pid" -o args= 2>/dev/null | grep -oP '127\.0\.0\.1:\K[0-9]+' | head -1)
        local remote_port="${cmdline:-unknown}"
        
        echo "$pid|$service_info|$namespace|$local_port|$remote_port"
    done <<< "$tunnel_info"
}

start_tunnel() {
    echo -e "${BLUE}🔍 Discovering NodePort services...${NC}"
    
    local services
    services=$(run_kubectl "get svc -A --field-selector spec.type=NodePort -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {range .spec.ports[*]}{.name}:{.port}:{.nodePort} {end}{\"\n\"}{end}'")
    
    if [ -z "$services" ]; then
      echo -e "${YELLOW}No NodePort services found.${NC}"
      read -p "Press Enter to return..."
      return
    fi

    # Get list of already-open remote ports from active tunnels
    local active_tunnel_data=$(discover_active_tunnels)
    local active_remote_ports=""
    if [ -n "$active_tunnel_data" ]; then
        active_remote_ports=$(echo "$active_tunnel_data" | cut -d'|' -f5 | grep -v '^unknown$' | tr '\n' ' ')
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
            if [[ " $active_remote_ports " == *" $p_nodeport "* ]]; then
                port_status=" ✓"
                has_active_tunnel=true
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
    selected_item=$(echo -e "$menu_items" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Start Tunnel > " --header="Select a service (✓ = already open)")

    if [ -z "$selected_item" ] || [[ "$selected_item" == "0. Back" ]]; then
      return
    fi

    # Remove [ACTIVE] marker if present
    selected_item="${selected_item% \[ACTIVE\]}"
    
    local svc_info="${selected_item%% *}"
    local namespace="${svc_info%%/*}"
    local service_name="${svc_info##*/}"
    local ports_info="${selected_item#* (}"
    ports_info="${ports_info%)}"

    local selected_port_mapping
    if [[ "$ports_info" == *", "* ]]; then
        local port_menu=$(echo "$ports_info" | sed 's/, /\n/g')
        selected_port_mapping=$(echo "$port_menu" | "$FZF_BIN" --height=20% --layout=reverse --border --prompt="Select Port > ")
    else
        selected_port_mapping="$ports_info"
    fi

    if [ -z "$selected_port_mapping" ]; then
        return
    fi

    # Remove ✓ marker if present
    selected_port_mapping="${selected_port_mapping% ✓}"
    
    local desired_port=$(echo "$selected_port_mapping" | awk -F'->' '{print $1}' | awk -F': ' '{print $2}')
    local remote_port=$(echo "$selected_port_mapping" | awk -F'->' '{print $2}')
    
    if ! [[ "$desired_port" =~ ^[0-9]+$ ]] || ! [[ "$remote_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error parsing ports.${NC}"
        read -p "Press Enter..."
        return
    fi

    # Auto-select available port
    echo -e "${BLUE}Finding available local port (base: $desired_port)...${NC}"
    local local_port=$(find_available_port "$desired_port")
    
    if [ "$local_port" != "$desired_port" ]; then
        echo -e "${YELLOW}Port $desired_port in use, using $local_port instead.${NC}"
    fi

    echo -e "${BLUE}Starting background tunnel for $svc_info ($local_port -> $remote_port)...${NC}"
    
    # Start SSH in background
    ssh -f -N -L "$local_port:127.0.0.1:$remote_port" \
        -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ExitOnForwardFailure=yes \
        "$MASTER_NODE"
    
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
        while IFS='|' read -r pid svc_info namespace local_port remote_port; do
            menu_items+="$svc_info (Local: $local_port -> Remote: $remote_port) [PID: $pid]\n"
        done <<< "$tunnel_data"

        menu_items+="0. Back"
        
        local selected
        selected=$(echo -e "$menu_items" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Manage Tunnels (Select to Stop) > " --header="Active Tunnels")

        if [ -z "$selected" ] || [[ "$selected" == "0. Back" ]]; then
            return
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

access_menu() {
  while true; do
    local actions="1. Start New Tunnel 🚀
2. Manage Active Tunnels 📋
0. Back"

    local selected_action
    selected_action=$(echo "$actions" | "$FZF_BIN" --height=20% --layout=reverse --border --prompt="Tunnel Manager > ")

    if [ -z "$selected_action" ]; then
      return
    fi

    case "${selected_action%%.*}" in
      1) start_tunnel ;;
      2) manage_tunnels ;;
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
    selected=$(echo -e "0. ← Back to Main Menu\n$cred_list" | "$FZF_BIN" \
      --height=40% \
      --layout=reverse \
      --border \
      --prompt="Search Credentials > " \
      --header="Type to search by name or description" \
      --preview="echo 'Select to view actions'" \
      --preview-window=down:2)
    
    if [ -z "$selected" ] || [[ "$selected" == "0. ← Back to Main Menu" ]]; then
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
      action=$(echo "$actions" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Action > ")
      
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
          edit_action=$(echo "$edit_menu" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Edit > ")
          
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
    local actions="1. Initialize Minio (Bucket + Access Keys) 🪣
2. Initialize Nexus (Blob Store + Docker Repo) 📦
3. Reset Nexus (Wipe Data & Restart) 🔄
4. Auto-Initialize All (Minio → Nexus) 🚀
0. Back"
    
    local selected
    selected=$(echo "$actions" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Service Configuration > " --header="Automated Service Setup")
    
    if [ -z "$selected" ] || [[ "$selected" == "0. Back" ]]; then
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
          read -p "Press Enter..."
          continue
        fi
        
        minio_initialize
        read -p "Press Enter to continue..."
        ;;
      2)
        clear
        echo -e "${BLUE}=== Nexus Initialization ===${NC}"
        echo ""
        
        # Check if Nexus is running
        if ! run_kubectl "get pods -n nexus -l app=nexus" | grep -q "Running"; then
          echo -e "${RED}Error: Nexus pod is not running${NC}"
          echo "Please deploy Nexus first via Component Management menu"
          read -p "Press Enter..."
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
        read -p "Press Enter to continue..."
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
          read -p "Press Enter..."
          continue
        fi
        
        nexus_reset
        read -p "Press Enter to continue..."
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
          read -p "Press Enter..."
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
          read -p "Press Enter..."
          continue
        }
        
        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}✓ All services initialized successfully!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        read -p "Press Enter to continue..."
        ;;
    esac
  done
}

# --- MAIN MENU ---

main_menu() {
  ensure_fzf

  while true; do
    local menu="1. Advanced Dashboard (k9s) 🚀
2. Open Kubernetes Dashboard (Browser) 🌐
3. Change Namespace (Current: $CURRENT_NS)
4. Select Pod
5. Show All Pods
6. Node Status
7. Safe Node Update (OS/Kernel) 🔄
8. Cluster Maintenance (Setup/Repair/Heal) 🛠️
9. Component Management (Deploy/Update) 📦
10. Access & Port Forwarding (SSH Tunnels) 🚇
11. Service Configuration (Minio/Nexus) ⚙️
12. View Credentials 🔐
0. Exit"

    local selected
    selected=$(echo "$menu" | "$FZF_BIN" --height=40% --layout=reverse --border --prompt="Main Menu > " --header="Cluster: $MASTER_NODE")

    if [ -z "$selected" ]; then
      exit 0
    fi

    case "${selected%%.*}" in
      1)
        open_k9s
        ;;
      2)
        open_dashboard
        ;;
      3)
        select_namespace
        ;;
      4)
        select_pod
        ;;
      5)
        clear
        run_kubectl "get pods -A -o wide" | less -S
        ;;
      6)
        clear
        run_kubectl "get nodes -o wide"
        read -p "Press Enter..."
        ;;
      7)
        clear
        ./safe_node_update.sh
        ;;
      8)
        cluster_maintenance_menu
        ;;
      9)
        component_management_menu
        ;;
      10)
        access_menu
        ;;
      11)
        service_config_menu
        ;;
      12)
        view_credentials_menu
        ;;
      0)
        echo "Bye!"
        exit 0
        ;;
    esac
  done
}

# Start
main_menu
