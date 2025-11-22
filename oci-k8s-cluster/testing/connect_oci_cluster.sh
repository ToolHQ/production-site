#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────
MASTER_PUBLIC_IP="150.136.34.254"
MASTER_PRIVATE_IP="10.0.1.100"
SSH_KEY="$HOME/.ssh/oci-ssh-key-2025-06-19.key"
KUBE_OCI="$HOME/.kube/oci-config"
KUBE_MINI="$HOME/.kube/config"
LOCAL_PORT=6443
TUNNEL_PID_FILE="/tmp/oci_tunnel.pid"
LOG_FILE="$HOME/.k8s-oci-history.log"
# ────────────────────────────────────────────────
# Colors & helpers
# ────────────────────────────────────────────────
C_RESET='\033[0m'
C_BLUE='\033[1;34m'
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_GRAY='\033[0;90m'

line() { echo -e "${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"; }
log()  { echo -e "${C_CYAN}$1${C_RESET}"; }
ok()   { echo -e "${C_GREEN}✅ $1${C_RESET}"; }
warn() { echo -e "${C_YELLOW}⚠️  $1${C_RESET}"; }
err()  { echo -e "${C_RED}❌ $1${C_RESET}"; }

# ────────────────────────────────────────────────
# Tunnel management
# ────────────────────────────────────────────────
start_tunnel() {
  if lsof -i :$LOCAL_PORT &>/dev/null; then
    warn "Port $LOCAL_PORT already in use."
    owner=$(lsof -ti :$LOCAL_PORT | xargs -r ps -o pid,cmd -p | tail -n +2 || true)
    echo -e "${C_YELLOW}Process using port $LOCAL_PORT:${C_RESET}"
    echo "$owner"
    read -rp "Kill it and restart the tunnel? [y/N]: " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      sudo lsof -ti :$LOCAL_PORT | xargs -r sudo kill -9 || true
      sleep 1
      warn "Old process killed. Restarting tunnel..."
    else
      err "Aborted due to port conflict."
      exit 1
    fi
  fi

  log "🌐 Starting SSH tunnel to $MASTER_PUBLIC_IP → $MASTER_PRIVATE_IP:$LOCAL_PORT ..."
  ssh -i "$SSH_KEY" -f -N -L "$LOCAL_PORT:$MASTER_PRIVATE_IP:$LOCAL_PORT" "ubuntu@$MASTER_PUBLIC_IP" || {
    err "Failed to start SSH tunnel."
    exit 1
  }

  sleep 1
  PID=$(pgrep -f "ssh -i $SSH_KEY -f -N -L $LOCAL_PORT:$MASTER_PRIVATE_IP:$LOCAL_PORT" | head -n 1 || true)
  if [[ -n "$PID" ]]; then
    echo "$PID" > "$TUNNEL_PID_FILE"
    ok "Tunnel active on https://127.0.0.1:$LOCAL_PORT (PID $PID)"
  else
    err "Could not verify SSH tunnel process."
  fi
}

stop_tunnel() {
  if [[ -f "$TUNNEL_PID_FILE" ]] && ps -p "$(cat "$TUNNEL_PID_FILE")" &>/dev/null; then
    log "🛑 Killing SSH tunnel..."
    kill "$(cat "$TUNNEL_PID_FILE")" && rm -f "$TUNNEL_PID_FILE"
    ok "Tunnel stopped."
  else
    warn "No active tunnel found."
  fi
}

# ────────────────────────────────────────────────
# Context setup
# ────────────────────────────────────────────────
connect_oci() {
  start_tunnel
  log "🛠️  Adjusting kubeconfig for localhost + insecure TLS..."
  sed -i 's#10\.0\.1\.100:6443#127.0.0.1:6443#g' "$KUBE_OCI"
  sed -i 's#insecure-skip-tls-verify: false#insecure-skip-tls-verify: true#g' "$KUBE_OCI"
  export KUBECONFIG="$KUBE_OCI"

  # 🧠 Ensure kubeconfig has valid server entry
  if ! grep -q "server: https://127.0.0.1:6443" "$KUBE_OCI"; then
    sed -i 's#server: ""#server: https://127.0.0.1:6443#g' "$KUBE_OCI"
    log "🔧 Fixed empty server entry in kubeconfig"
  fi

  log "🔧 kubeconfig now points to:       server: https://127.0.0.1:6443"
  log "🔎 Verifying connectivity..."

  # Retry loop for slow tunnel startup
  success=false
  for i in {1..5}; do
    if kubectl cluster-info >/dev/null 2>&1; then
      success=true
      break
    else
      warn "Attempt $i/5: waiting for API to respond..."
      sleep 2
    fi
  done

  if [ "$success" != true ]; then
    err "❌ ❌ Failed to connect. Verify SSH tunnel PID $SSH_TUNNEL_PID and kubeconfig path $KUBE_OCI"
    stop_tunnel
    return 1
  fi

  ok "Connected to OCI cluster. Entering interactive mode..."
  kubectl get nodes -o wide

  line
  echo -e "${C_CYAN}💬 Type any kubectl / helm / bash command below (type 'exit' to quit):${C_RESET}"
  line
  echo -e "${C_GRAY}(Logging to $LOG_FILE)${C_RESET}\n"

  # Graceful cleanup if interrupted
  trap 'warn "Leaving OCI shell..."; stop_tunnel; exit 0' INT TERM

  while true; do
    read -rp "$(echo -e "${C_GREEN}[OCI]${C_RESET} > ")" cmd
    [[ "$cmd" == "exit" ]] && break
    [[ -z "$cmd" ]] && continue

    echo -e "\n--- $(date '+%Y-%m-%d %H:%M:%S') | CMD: $cmd ---" >> "$LOG_FILE"
    bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE"
  done

  trap - INT TERM
  line
  warn "Leaving OCI shell..."
  stop_tunnel
}

connect_minikube() {
  export KUBECONFIG="$KUBE_MINI"
  log "🔎 Switching to local Minikube context..."
  if kubectl cluster-info &>/dev/null; then
    ok "Connected to Minikube."
    kubectl get nodes -o wide
    echo -e "\n${C_GRAY}(Logging to $LOG_FILE)${C_RESET}\n"
    while true; do
      read -rp "$(echo -e "${C_YELLOW}[Mini]${C_RESET} > ")" cmd
      [[ "$cmd" == "exit" ]] && break
      [[ -z "$cmd" ]] && continue

      echo -e "\n--- $(date '+%Y-%m-%d %H:%M:%S') | CMD: $cmd ---" >> "$LOG_FILE"
      bash -c "$cmd" 2>&1 | tee -a "$LOG_FILE"
    done
    line
    warn "Leaving Minikube shell..."
  else
    err "Minikube not running. Start it with: minikube start"
  fi
}

# ────────────────────────────────────────────────
# Menu
# ────────────────────────────────────────────────
main_menu() {
  clear
  line
  echo -e " 🌐  ${C_BLUE}Kubernetes Context Switcher${C_RESET}"
  line
  echo "1) Connect to OCI cluster (interactive shell)"
  echo "2) Connect to Minikube (local dev)"
  echo "3) Disconnect / stop tunnels"
  echo "4) Exit"
  line
  read -rp "Select an option [1-4]: " choice

  case "$choice" in
    1) connect_oci ;;
    2) connect_minikube ;;
    3) stop_tunnel ;;
    4) exit 0 ;;
    *) warn "Invalid option"; sleep 1; main_menu ;;
  esac
}

main_menu
