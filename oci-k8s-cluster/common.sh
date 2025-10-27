#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────
# Common functions and variables for OCI K8s cluster scripts
# ────────────────────────────────────────────────
if grep -q 'Host oci-k8s-' ~/.ssh/config; then
  mapfile -t NODES < <(grep -E '^Host oci-k8s-' ~/.ssh/config | awk '{print $2}')
  echo "🔍 Auto-detected nodes: ${NODES[*]}"
else
  echo "⚠️  No oci-k8s-* hosts found; using defaults."
  NODES=(oci-k8s-master oci-k8s-node-1 oci-k8s-node-2)
fi

MASTER_NODE="${NODES[0]}"
WORKER_NODES=("${NODES[@]:1}")
K8S_VERSION="1.34.1"
POD_CIDR="192.168.0.0/16"   # Pod CIDR; Cilium runs in VXLAN overlay
SERVICE_CIDR="10.96.0.0/12" # kubeadm default
CILIUM_VERSION="1.18.3"     # exact
CILIUM_CLI_VERSION="0.18.7"
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
  ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -n -T "$node" "$@" 2>&1 | sed "s/^/[$node] /"
}
run_remote_stream() {
  local node=$1; shift
  log_node "$node" "▶ (streamed) $*"
  ssh -o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -n -T "$node" "$@" 2>&1 | while IFS= read -r line; do echo "[$node] $line"; done
}
run_remote_capture() {
  local node=$1; shift
  local cmd="$*"

  log_node "$node" "→ $cmd"

  # Capture both output and exit code
  local output
  output=$(ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
              -n -T "$node" "$cmd" 2>&1)
  local status=$?

  # Prefix each output line for readability
  if [[ -n "$output" ]]; then
    echo "$output" | sed "s/^/[$node] /"
  fi

  # Return result via global or echo
  RUN_REMOTE_CAPTURE_RESULT="$output"   # for later access
  return $status
}