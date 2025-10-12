#!/usr/bin/env bash
# ---------------------------------------------------------------
# OCI A1.Flex ARM Kubernetes cluster bootstrapper (WSL launcher)
# Author: Daniel / ChatGPT automation
# Run from WSL (Ubuntu) with SSH access configured in ~/.ssh/config
# - Installs containerd + kubeadm/kubelet/kubectl (v1.30)
# - Sets kernel modules/sysctls, disables swap
# - Applies flannel CNI (flannel-io) and waits for API readiness
# - Joins workers, tolerating 1 vCPU with --ignore-preflight-errors=NumCPU
# - Verifies full cluster health post-setup
# ---------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------
NODES=(oci-k8s-master oci-k8s-node-1 oci-k8s-node-2 oci-k8s-node-3)
MASTER_NODE="${NODES[0]}"

# ---------------------------------------------------------------
# UTILITIES
# ---------------------------------------------------------------
update_node() {
  local host=$1
  echo "🔹 Updating $host ..."
  ssh "$host" 'sudo apt-get update -y &&
               sudo apt-get upgrade -y &&
               sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release jq'
}

install_containerd() {
  local host=$1
  echo "🔹 Installing containerd on $host ..."
  ssh "$host" '
    sudo apt-get install -y containerd &&
    sudo mkdir -p /etc/containerd &&
    sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null &&
    sudo sed -i "s/SystemdCgroup = false/SystemdCgroup = true/" /etc/containerd/config.toml &&
    sudo systemctl enable --now containerd
  '
}

install_k8s_pkgs() {
  local host=$1
  echo "🔹 Installing Kubernetes packages on $host ..."
  ssh "$host" '
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
      | sudo gpg --dearmor --yes --batch \
      -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
      | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo systemctl enable kubelet
  '
}

tune_sysctl() {
  local host=$1
  echo "🔹 Tuning kernel networking on $host ..."
  ssh "$host" '
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
  ssh "$MASTER_NODE" '
    set -e
    sudo kubeadm reset -f || true
    sudo kubeadm init \
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
  ssh "$MASTER_NODE" 'kubeadm token create --print-join-command' > join_cmd.sh
  echo "✅ Join command saved to $(pwd)/join_cmd.sh"
}

# ---------------------------------------------------------------
# WORKER NODES
# ---------------------------------------------------------------
join_workers() {
  local join_cmd
  join_cmd=$(tr -d '\r\n' < join_cmd.sh)
  local master_ip
  master_ip=$(ssh "$MASTER_NODE" "hostname -I | awk '{print \$1}'")

  # Optional: wait until CoreDNS/flannel are rolling out to reduce join hiccups
  echo "⏳ Giving the control plane a moment to settle..."
  sleep 20

  # --- NEW: verify connectivity to master before joining
  echo "🔎 Checking connectivity to master ($master_ip:6443)..."
  for w in "${NODES[@]:1}"; do
    echo "🧠 Flushing ARP cache and testing from $w ..."
    ssh "$w" "
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
    ssh "$w" "
      sudo kubeadm reset -f || true
      sudo ${join_cmd} --ignore-preflight-errors=NumCPU
    "
  done
}

# ---------------------------------------------------------------
# MAIN EXECUTION
# ---------------------------------------------------------------
for n in "${NODES[@]}"; do
  update_node "$n"
  tune_sysctl "$n"
  install_containerd "$n"
  install_k8s_pkgs "$n"
done

init_master
join_workers
verify_cluster

cat <<'NOTE'

✅ Done!

If workers still fail to join, make sure your **OCI Security List / NSG** allows
intra-VCN traffic for these *private* ports (Source = your VCN CIDR, e.g. 10.0.0.0/16):

- TCP 6443   (API server)
- UDP 8472   (Flannel VXLAN)
- TCP 10250  (kubelet metrics)
- ICMP type 8 code 0 (internal ping)

Then re-run on each worker:
  sudo kubeadm reset -f
  sudo $(cat ~/setup/join_cmd.sh) --ignore-preflight-errors=NumCPU

NOTE
