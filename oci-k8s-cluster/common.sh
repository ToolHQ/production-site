#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────
# Color Definitions
# ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ────────────────────────────────────────────────
# Common functions and variables for OCI K8s cluster scripts
# ────────────────────────────────────────────────

# Ensure SCRIPT_DIR is set (robust for sourcing or direct execution)
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Only detect nodes if not already set (cache across multiple sourcing)
if [ -z "${NODES+x}" ]; then
  if grep -q 'Host oci-k8s-' ~/.ssh/config; then
    mapfile -t NODES < <(grep -E '^Host oci-k8s-' ~/.ssh/config | awk '{print $2}')
    echo "🔍 Auto-detected nodes:"
    for n in "${NODES[@]}"; do
      echo "   • $n"
    done
  else
    echo "⚠️  No oci-k8s-* hosts found; using defaults."
    NODES=(oci-k8s-master oci-k8s-node-1 oci-k8s-node-2 oci-k8s-node-3)
  fi
fi

# Alias for scripts expecting CLUSTER_NODES
CLUSTER_NODES=("${NODES[@]}")

MASTER_PUBLIC_IP="150.136.34.254"
MASTER_PRIVATE_IP="10.0.1.100"
MASTER_NODE="${NODES[0]}"
WORKER_NODES=("${NODES[@]:1}")

# External servers (not K8s nodes, but part of the infrastructure fleet)
# shellcheck disable=SC2034
# BEGIN EXTERNAL_FLEET_NODES
EXTERNAL_NODES=(
  "hetzner-cax21-helsinki-4vcpu-8gb-ipv4"  # HETZNER @ 37.27.85.100
  "ssdnodes-monstro"  # SSD-NODES @ 104.225.218.78
  "aws-ec2-fleet-01"  # AWS-EC2 @ honeypot.dnor.io
)
# END EXTERNAL_FLEET_NODES
# Full fleet: cluster nodes + external servers
# shellcheck disable=SC2034
ALL_FLEET_NODES=("${CLUSTER_NODES[@]}" "${EXTERNAL_NODES[@]}")

K8S_VERSION="1.34.1"
POD_CIDR="192.168.0.0/16"   # Pod CIDR; Cilium runs in VXLAN overlay
SERVICE_CIDR="10.96.0.0/12" # kubeadm default
CILIUM_VERSION="1.18.3"     # exact
CILIUM_CLI_VERSION="0.18.7"
LONGHORN_VERSION="1.10.1"   # Longhorn stable version
CERT_MANAGER_VERSION="v1.13.0" # cert-manager version
STORAGE_PROVISIONER="${STORAGE_PROVISIONER:-longhorn}" # Default: longhorn, alternative: local-path
NEXUS_IP="${NEXUS_IP:-10.99.219.185}" # Centralized IP for internal registry mirror
SSH_KEY="${SSH_KEY:-$HOME/.ssh/oci-ssh-key-2025-06-19.key}"
RUN_REMOTE_CAPTURE_RESULT=""

# Source Audit Library
if [[ -f "${SCRIPT_DIR:-}/lib/audit.sh" ]]; then
    source "${SCRIPT_DIR:-}/lib/audit.sh"
elif [[ -f "$(dirname "$0")/lib/audit.sh" ]]; then
    source "$(dirname "$0")/lib/audit.sh"
fi

# Source Credential Store Library
if [[ -f "${SCRIPT_DIR:-}/lib/credstore.sh" ]]; then
    source "${SCRIPT_DIR:-}/lib/credstore.sh"
elif [[ -f "$(dirname "$0")/lib/credstore.sh" ]]; then
    source "$(dirname "$0")/lib/credstore.sh"
fi

# === Helpers ====================================================
log_node() { 
  # $1 = node name, $2+ = message
  local node="$1"
  shift
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  printf "\033[90m[%s]\033[0m \033[1;36m[%s]\033[0m %s\n" "$ts" "$node" "$*"
}

run_remote() {
  local node=$1; shift
  log_node "$node" "→ $*"
  local retries=3
  local count=0
  local delay=5

  while [ $count -lt $retries ]; do
    if ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new \
        -n -T "$node" "$@" 2>&1 | sed "s/^/[$node] /"; then
      return 0
    else
      local exit_code=$?
      # If exit code is 255 (SSH error), retry. Otherwise (command error), fail immediately.
      if [ $exit_code -eq 255 ]; then
        ((count++))
        echo "[$node] ⚠️  SSH connection failed (attempt $count/$retries). Retrying in ${delay}s..." >&2
        sleep $delay
      else
        return $exit_code
      fi
    fi
  done
  echo "[$node] ❌ SSH failed after $retries attempts." >&2
  return 255
}

run_remote_stream() {
  local node=$1; shift
  log_node "$node" "▶ (streamed) $*"
  local retries=3
  local count=0
  local delay=5

  # Detect if stdin is connected to a terminal or a pipe/heredoc
  local use_tty="-T"
  if [ -t 0 ]; then
    use_tty="-n -T"
  fi

  while [ $count -lt $retries ]; do
    if ssh $use_tty -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=accept-new \
        "$node" "$@" 2>&1 | while IFS= read -r line; do echo "[$node] $line"; done; then
      return 0
    else
       local exit_code=${PIPESTATUS[0]}
       if [ $exit_code -eq 255 ]; then
        ((count++))
        echo "[$node] ⚠️  SSH connection failed (attempt $count/$retries). Retrying in ${delay}s..." >&2
        sleep $delay
      else
        return $exit_code
      fi
    fi
  done
  echo "[$node] ❌ SSH failed after $retries attempts." >&2
  return 255
}

run_remote_capture() {
  local node=$1; shift
  local cmd="$*"
  log_node "$node" "→ $cmd"

  local retries=3
  local count=0
  local delay=5
  local output
  local status

  while [ $count -lt $retries ]; do
    output=$(ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new \
                -n -T "$node" "$cmd" 2>&1)
    status=$?

    if [ $status -eq 255 ]; then
       ((count++))
       echo "[$node] ⚠️  SSH connection failed (attempt $count/$retries). Retrying in ${delay}s..." >&2
       sleep $delay
    else
       # Success or command error - process output and return
       if [[ -n "$output" ]]; then
         echo "$output" | sed "s/^/[$node] /"
       fi
       RUN_REMOTE_CAPTURE_RESULT="$output"
       return $status
    fi
  done
  
  echo "[$node] ❌ SSH failed after $retries attempts." >&2
  return 255
}

run_remote_raw() {
  local node="$1"
  shift
  log_node "$node" "$@" >&2

  local retries=3
  local count=0
  local delay=5

  while [ $count -lt $retries ]; do
    if ssh -o BatchMode=yes \
        -o ConnectTimeout=20 \
        -o StrictHostKeyChecking=accept-new \
        -n -T "$node" "$@"; then
      return 0
    else
      local exit_code=$?
      if [ $exit_code -eq 255 ]; then
        ((count++))
        echo "[$node] ⚠️  SSH connection failed (attempt $count/$retries). Retrying in ${delay}s..." >&2
        sleep $delay
      else
        return $exit_code
      fi
    fi
  done
  return 255
}

scp_to_remote() {
  local node="$1"
  local src="$2"
  local dest="$3"
  scp -r -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new \
      "$src" "$node:$dest"
  log_node "$node" "📤 Copied $src to $dest"
}

# Kill any local SSH tunnel listening on a given port
# Usage: kill_local_tunnel <port>
kill_local_tunnel() {
  local port="$1"
  if [[ -z "$port" ]]; then
    echo "⚠️  No port provided to kill_local_tunnel"
    return 1
  fi

  if command -v lsof >/dev/null 2>&1; then
    local pid
    pid=$(lsof -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
      kill "$pid" && echo "🧹 Closed local listener on port $port (pid $pid)."
    fi
  else
    pkill -f "ssh.*-L.*${port}:.*:.*" 2>/dev/null && echo "🧹 Closed ssh tunnel(s) on port $port."
  fi
}

# Helper to run kubectl on master
run_kubectl() {
  run_remote_raw "$MASTER_NODE" "kubectl $*"
}

# Audio Alert (WSL Compatible)
# Audio Alert (WSL Compatible)
alert_sound() {
    # Method 1: PowerShell SystemSound (Most reliable on WSL)
    if grep -q "microsoft" /proc/version 2>/dev/null; then
         powershell.exe -c "(New-Object Media.SoundPlayer 'C:\Windows\Media\tada.wav').PlaySync();" 2>/dev/null &
         return
    fi

    # Method 2: xdg-open (Linux Desktop / setup pending)
    if command -v xdg-open >/dev/null 2>&1; then
        # This is often silent on servers, but user requested it
        return
    fi

    # Method 3: Standard Bell (Fallback)
    echo -e "\a"
}