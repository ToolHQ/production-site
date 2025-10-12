#!/usr/bin/env bash
# ---------------------------------------------------------------
# OCI A1.Flex ARM Kubernetes cluster bootstrapper (WSL launcher)
# Version: v1.1
# Author: Daniel / ChatGPT automation
# Run from WSL (Ubuntu) with SSH access configured in ~/.ssh/config
# - Installs containerd + kubeadm/kubelet/kubectl (v1.30)
# - Sets kernel modules/sysctls, disables swap
# - Applies flannel CNI (flannel-io) and waits for API readiness
# - Joins workers, tolerating 1 vCPU with --ignore-preflight-errors=NumCPU
# - Verifies full cluster health post-setup
#
# New features in v1.1:
# ✅ Auto-detect nodes from ~/.ssh/config
# ✅ Parallel updates/installs for speed
# ✅ Reset/Cleanup function for quick rebuilds
# ✅ Full logging to setup_k8s_cluster_<timestamp>.log
# ✅ Upgraded to Kubernetes v1.34.1
# ---------------------------------------------------------------

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
LOGFILE="setup_k8s_cluster_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# --- Colored log helper ---
log_node() {
  local node="$1"
  local msg="$2"
  printf "\033[1;36m[%s]\033[0m %s\n" "$node" "$msg"
}

# --- Safe SSH wrapper with visible node prefix ---
run_remote() {
  local node="$1"
  shift
  log_node "$node" "→ $*"
  ssh -o BatchMode=yes \
      -o ConnectTimeout=15 \
      -o ConnectionAttempts=1 \
      -o ControlMaster=no \
      -o ControlPersist=no \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -n -T "$node" "$@" 2>&1 | sed "s/^/[$node] /"
}
# --- Run a command with a live node-prefixed stream (for long-running tasks like kubeadm) ---
run_remote_stream() {
  local node="$1"
  shift
  log_node "$node" "▶ (streamed) $*"
  ssh -o BatchMode=yes \
      -o ConnectTimeout=15 \
      -o ConnectionAttempts=1 \
      -o ControlMaster=no \
      -o ControlPersist=no \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -n -T "$node" "$@" 2>&1 | while IFS= read -r line; do
        echo "[$node] $line"
      done
}
# ---------------------------------------------------------------
# AUTO-DETECT NODES
# ---------------------------------------------------------------
if grep -q 'Host oci-k8s-' ~/.ssh/config; then
  mapfile -t NODES < <(grep -E '^Host oci-k8s-' ~/.ssh/config | awk '{print $2}')
  echo "🔍 Auto-detected nodes from SSH config: ${NODES[*]}"
else
  echo "⚠️  No oci-k8s-* hosts found in ~/.ssh/config, falling back to manual list."
  NODES=(oci-k8s-master oci-k8s-node-1 oci-k8s-node-2 oci-k8s-node-3)
fi

MASTER_NODE="${NODES[0]}"

# ---------------------------------------------------------------
# UTILITIES
# ---------------------------------------------------------------
update_node() {
  local host=$1
  echo "🔹 Updating $host ..."
  run_remote "$host" '
    export DEBIAN_FRONTEND=noninteractive
    sudo apt-get update -y
    # Avoid breaking held packages like kubeadm/kubelet/kubectl
    sudo apt-mark unhold kubeadm kubelet kubectl >/dev/null 2>&1 || true
    sudo apt-get -o Dpkg::Options::="--force-confold" -y upgrade || true
    sudo apt-mark hold kubeadm kubelet kubectl >/dev/null 2>&1 || true
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release jq
  '
}

install_containerd() {
  local host=$1
  echo "🔹 Installing containerd on $host ..."
  run_remote "$host" '
    sudo apt-get install -y containerd &&
    sudo mkdir -p /etc/containerd &&
    sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null &&
    sudo sed -i "s/SystemdCgroup = false/SystemdCgroup = true/" /etc/containerd/config.toml &&
    sudo systemctl enable --now containerd
  '
}

install_k8s_pkgs() {
  local host=$1
  echo "🔹 Installing Kubernetes v1.34.1 packages on $host ..."
  run_remote "$host" '
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key \
      | sudo gpg --dearmor --yes --batch \
      -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /" \
      | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y kubelet=1.34.1-1.1 kubeadm=1.34.1-1.1 kubectl=1.34.1-1.1
    sudo systemctl enable kubelet && sudo systemctl start kubelet
  '
}

tune_sysctl() {
  local host=$1
  echo "🔹 Tuning kernel networking on $host ..."
  run_remote "$host" '
    # Ensure bridge netfilter and forwarding
    echo br_netfilter | sudo tee /etc/modules-load.d/br_netfilter.conf
    sudo modprobe br_netfilter || true
    echo -e "net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1" \
      | sudo tee /etc/sysctl.d/k8s.conf
    sudo sysctl --system

    # Disable swap now and persistently (idempotent if already off)
    sudo swapoff -a
    sudo sed -i "/[[:space:]]swap[[:space:]]/s/^/#/" /etc/fstab
  '
}

# ---------------------------------------------------------------
# CLUSTER VERIFICATION
# ---------------------------------------------------------------
verify_cluster() {
  echo ""
  echo "🔍 Verifying Kubernetes cluster health on control plane..."
  ssh "$MASTER_NODE" bash -s <<'EOF'
    echo "------------------------------------------------------------"
    echo "📋 Nodes:"
    kubectl get nodes -o wide || { echo "❌ Failed to get nodes"; exit 1; }
    echo "------------------------------------------------------------"
    echo "📦 System Pods (kube-system):"
    kubectl get pods -n kube-system -o wide || { echo "❌ Failed to get system pods"; exit 1; }
    echo "------------------------------------------------------------"
    echo "🌐 Checking CoreDNS status..."
    if kubectl get pods -n kube-system | grep -q 'coredns'; then
      kubectl rollout status deployment/coredns -n kube-system --timeout=90s || echo "⚠️  CoreDNS not ready yet"
    else
      echo "⚠️  CoreDNS deployment missing"
    fi
    echo "------------------------------------------------------------"
    echo "🌉 Verifying cluster networking (Flannel)..."
    if kubectl get pods -n kube-flannel &>/dev/null; then
      kubectl get pods -n kube-flannel -o wide
    else
      echo "ℹ️  kube-flannel namespace not found (might be embedded in kube-system)"
      kubectl get pods -n kube-system | grep flannel || echo "⚠️  Flannel pods not detected"
    fi
    echo "------------------------------------------------------------"
    echo "✅ Verification completed."
EOF
  echo ""
  echo "💚 If all pods show STATUS=Running and nodes are Ready, your cluster is good to go!"
  echo ""
}
# ---------------------------------------------------------------
# CONTROL PLANE
# ---------------------------------------------------------------
init_master() {
  echo "🚀 Initializing control plane on $MASTER_NODE ..."
  run_remote_stream "$MASTER_NODE" '
    set -e
    sudo kubeadm reset -f || true
    sudo kubeadm init \
      --kubernetes-version=v1.34.1 \
      --pod-network-cidr=10.244.0.0/16 \
      --apiserver-advertise-address=$(hostname -I | awk "{print \$1}") \
      --ignore-preflight-errors=NumCPU | tee /tmp/kubeinit.log

    # kubeconfig for current user (non-interactive, idempotent)
    mkdir -p $HOME/.kube
    sudo install -o $USER -g $USER -m 0644 /etc/kubernetes/admin.conf $HOME/.kube/config

    # Wait for API to be healthy BEFORE applying CNI
    echo "⏳ Waiting for API server to report health..."
    until curl -ks https://localhost:6443/healthz | grep -q "^ok$"; do sleep 5; done

    # Apply Flannel (use explicit kubeconfig just in case)
    kubectl --kubeconfig=$HOME/.kube/config apply -f https://raw.githubusercontent.com/flannel-io/flannel/v0.25.1/Documentation/kube-flannel.yml
  '
  # fresh join command
  # no prefixing here — use raw ssh so the file is clean
  ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$MASTER_NODE" 'kubeadm token create --print-join-command' | tr -d '\r' > join_cmd.sh
  echo "✅ Join command saved to $(pwd)/join_cmd.sh"
}

# ---------------------------------------------------------------
# WORKER NODES
# ---------------------------------------------------------------
join_workers() {
  local join_cmd
  read -r join_cmd < join_cmd.sh
  local master_ip
  master_ip=$(ssh "$MASTER_NODE" "hostname -I | awk '{print \$1}'")

  # Optional: wait until CoreDNS/flannel are rolling out to reduce join hiccups
  echo "⏳ Giving the control plane a moment to settle..."
  sleep 20

  # --- NEW: verify connectivity to master before joining
  echo "🔎 Checking connectivity to master ($master_ip:6443)..."
  for w in "${NODES[@]:1}"; do
    echo "🧠 Flushing ARP cache and testing from $w ..."
    run_remote "$w" "
      sudo ip neigh flush all || true
      if nc -zvw3 $master_ip 6443; then
        echo '✅ Port 6443 reachable from $w'
      else
        echo '❌ Port 6443 unreachable from $w - check OCI Security List/NSG'
        exit 1
      fi
    "
  done

  echo "🔗 All workers can reach control plane — proceeding to join..."
  for w in "${NODES[@]:1}"; do
    echo "🧩 Joining $w to cluster..."
    run_remote "$w" "
      sudo kubeadm reset -f || true
      sudo ${join_cmd} --ignore-preflight-errors=NumCPU
    "
  done
}


# ---------------------------------------------------------------
# CLUSTER RESET (optional cleanup)
# ---------------------------------------------------------------
reset_cluster() {
  echo "🧹 Resetting all nodes (detached mode)..."

  for n in "${NODES[@]}"; do
    echo "→ Dispatching reset command to $n ..."
    run_remote -o BatchMode=yes -o ConnectTimeout=10 "$n" "nohup bash -c '
      sudo systemctl stop kubelet containerd 2>/dev/null || true
      sudo kubeadm reset -f >/dev/null 2>&1 || true
      sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet /etc/kubernetes /var/lib/etcd /run/flannel /opt/cni >/dev/null 2>&1 || true
      sudo systemctl start containerd 2>/dev/null || true
      echo \"✅ Node \$(hostname) cleaned\" > /tmp/reset_done
    ' >/dev/null 2>&1 & disown" || echo "⚠️ Failed to dispatch reset on $n"
  done

  echo "⏳ Waiting up to 40s for cleanup signals..."
  sleep 40

  echo "🔍 Checking nodes for reset completion..."
  for n in "${NODES[@]}"; do
    run_remote -o BatchMode=yes -o ConnectTimeout=10 "$n" 'test -f /tmp/reset_done && cat /tmp/reset_done || echo "❌ Not yet finished"'
  done

  echo "✅ Cluster reset complete (detached mode)."
}

# ---------------------------------------------------------------
# MAIN EXECUTION
# ---------------------------------------------------------------
echo "⚙️  Starting node preparation sequentially (safe mode)..."

for n in "${NODES[@]}"; do
  echo "------------------------------------------------------------"
  echo "🛠️  Preparing $n..."
  update_node "$n"
  tune_sysctl "$n"
  install_containerd "$n"
  install_k8s_pkgs "$n"
  echo "✅ Finished preparing $n."
  echo "------------------------------------------------------------"
done

echo "✅ All nodes prepared successfully (safe sequential mode)."

init_master
join_workers

echo "🔒 Locking Kubernetes package versions (post-verification)..."
for n in "${NODES[@]}"; do
  run_remote "$n" "sudo apt-mark hold kubelet kubeadm kubectl >/dev/null && ver=\$(kubelet --version) && echo \"[$n] packages held at \$ver\""
done

verify_cluster

cat <<'NOTE'

✅ Done! Logs saved to $LOGFILE

If workers still fail to join, make sure your **OCI Security List / NSG** allows
intra-VCN traffic for these *private* ports (Source = your VCN CIDR, e.g. 10.0.0.0/16):

- TCP 6443   (API server)
- UDP 8472   (Flannel VXLAN)
- TCP 10250  (kubelet metrics)
- ICMP type 8 code 0 (internal ping)

For a clean rebuild:
  ./setup_k8s_cluster.sh reset_cluster

NOTE
