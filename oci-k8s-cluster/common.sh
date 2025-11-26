#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────
# Common functions and variables for OCI K8s cluster scripts
# ────────────────────────────────────────────────
if grep -q 'Host oci-k8s-' ~/.ssh/config; then
  mapfile -t NODES < <(grep -E '^Host oci-k8s-' ~/.ssh/config | awk '{print $2}')
  echo "🔍 Auto-detected nodes:"
  for n in "${NODES[@]}"; do
    echo "   • $n"
  done
else
  echo "⚠️  No oci-k8s-* hosts found; using defaults."
  NODES=(oci-k8s-master oci-k8s-node-1 oci-k8s-node-2)
fi

MASTER_PUBLIC_IP="150.136.34.254"
MASTER_NODE="${NODES[0]}"
WORKER_NODES=("${NODES[@]:1}")
K8S_VERSION="1.34.1"
POD_CIDR="192.168.0.0/16"   # Pod CIDR; Cilium runs in VXLAN overlay
SERVICE_CIDR="10.96.0.0/12" # kubeadm default
CILIUM_VERSION="1.18.3"     # exact
CILIUM_CLI_VERSION="0.18.7"
LONGHORN_VERSION="1.10.1"   # Longhorn stable version
CERT_MANAGER_VERSION="v1.13.0" # cert-manager version
STORAGE_PROVISIONER="${STORAGE_PROVISIONER:-longhorn}" # Default: longhorn, alternative: local-path
SSH_KEY="${SSH_KEY:-$HOME/.ssh/oci-ssh-key-2025-06-19.key}"
RUN_REMOTE_CAPTURE_RESULT=""

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
    if ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
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
    if ssh $use_tty -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
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
    output=$(ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
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
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
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
  scp -r -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
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