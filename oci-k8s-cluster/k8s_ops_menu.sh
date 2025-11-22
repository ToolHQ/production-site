#!/usr/bin/env bash
set -euo pipefail

# Source common configuration for SSH keys and node info
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
  
  # 2. Setup Tunnel (SSH -> ClusterIP)
  echo "Setting up secure connection (SSH Tunnel to ClusterIP)..."
  
  # CLEANUP: Kill local processes on 8443
  if lsof -ti:8443 >/dev/null 2>&1; then
    echo "Freeing local port 8443..."
    kill -9 $(lsof -ti:8443) 2>/dev/null || true
  fi
  
  # Get ClusterIP
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
  
  # Start SSH Tunnel
  # Local 8443 -> SSH(Master) -> ClusterIP:443
  # This works because the Master node can route to ClusterIPs.
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -f -N -L 8443:${cluster_ip}:443 \
      "$MASTER_NODE"
  
  echo "Waiting for tunnel to establish..."
  local retries=0
  while ! nc -z localhost 8443 >/dev/null 2>&1; do
    sleep 1
    ((retries++))
    if [ $retries -gt 10 ]; then
      echo -e "${RED}Timeout waiting for tunnel.${NC}"
      read -p "Press Enter..."
      return
    fi
  done
  
  local url="https://localhost:8443/#/workloads?namespace=_all"
  
  # 3. Display and Open
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
  
  read -p "Press Enter to stop tunnel and return..."
  
  # Cleanup on exit
  if lsof -ti:8443 >/dev/null 2>&1; then
    kill -9 $(lsof -ti:8443) 2>/dev/null || true
  fi
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

main_menu() {
  ensure_fzf

  while true; do
    local menu="1. Advanced Dashboard (k9s) 🚀
2. Open Kubernetes Dashboard (Browser) 🌐
3. Change Namespace (Current: $CURRENT_NS)
4. Select Pod
5. Show All Pods
6. Node Status
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
      0)
        echo "Bye!"
        exit 0
        ;;
    esac
  done
}

# Start
main_menu
