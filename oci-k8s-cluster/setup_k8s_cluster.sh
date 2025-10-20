#!/usr/bin/env bash
# ---------------------------------------------------------------
# OCI A1.Flex ARM Kubernetes cluster bootstrapper (Cilium edition)
# Version: v2.0 (Cilium 1.18.2, direct routing, deep CNI cleanup)
# ---------------------------------------------------------------

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
LOGFILE="setup_k8s_cluster_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

# === CONFIG =====================================================
# Auto-detect oci-k8s-* from ~/.ssh/config; fallback to defaults.
if grep -q 'Host oci-k8s-' ~/.ssh/config; then
  mapfile -t NODES < <(grep -E '^Host oci-k8s-' ~/.ssh/config | awk '{print $2}')
  echo "🔍 Auto-detected nodes: ${NODES[*]}"
else
  echo "⚠️  No oci-k8s-* hosts found; using defaults."
  NODES=(oci-k8s-master oci-k8s-node-1 oci-k8s-node-2)
fi

MASTER_NODE="${NODES[0]}"
K8S_VERSION="1.34.1"
POD_CIDR="192.168.0.0/16"   # Cilium native routing CIDR (no overlay)
SERVICE_CIDR="10.96.0.0/12" # kubeadm default
CILIUM_VERSION="1.18.2"     # exact
CILIUM_CLI_VERSION="0.18.7"

# === Helpers ====================================================
log_node() { printf "\033[1;36m[%s]\033[0m %s\n" "$1" "$2"; }
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

# === API server openness (master) ============================================
ensure_apiserver_open() {
  local h=$1
  run_remote_stream "$h" '
    set -e

    # 1) Confirm apiserver is listening
    echo "🔎 Checking kube-apiserver listening sockets…"
    ss -ltnp | awk '"'"'/LISTEN/ && /:6443/ {print $0}'"'"' || true

    if ! ss -ltn "( sport = :6443 )" | grep -q LISTEN; then
      echo "❌ kube-apiserver not listening on 6443; will try to ensure bind-address."
      NEED_BIND=1
    else
      # If bound to 127.0.0.1 only, we must widen it.
      if ss -ltn | awk '"'"'/LISTEN/ && /:6443/ && !/0\.0\.0\.0|:::/ {print}'"'"' | grep -q 6443; then
        echo "⚠️  kube-apiserver listening but not on 0.0.0.0/:: — will set bind-address."
        NEED_BIND=1
      else
        NEED_BIND=0
      fi
    fi

    # 2) If needed, inject --bind-address=0.0.0.0 into the static pod manifest
    if [ "${NEED_BIND:-0}" -eq 1 ]; then
      echo "📝 Patching /etc/kubernetes/manifests/kube-apiserver.yaml with --bind-address=0.0.0.0"
      sudo sed -i '"'"'/\- kube-apiserver/a\    - --bind-address=0.0.0.0'"'"' /etc/kubernetes/manifests/kube-apiserver.yaml
      echo "⏳ Waiting for apiserver to restart…"
      sleep 8
      # wait until healthz ok
      until curl -ks https://localhost:6443/healthz | grep -q "^ok$"; do sleep 2; done
      echo "✅ kube-apiserver healthy"
    fi

    # 3) Ensure host firewall allows TCP/6443 (iptables) — add only if missing
    if command -v iptables >/dev/null 2>&1; then
      if ! sudo iptables -C INPUT -p tcp --dport 6443 -j ACCEPT 2>/dev/null; then
        echo "🔓 Allowing TCP/6443 in iptables (INPUT)…"
        sudo iptables -I INPUT 1 -p tcp --dport 6443 -j ACCEPT || true
      fi
      # Keep established/related (cheap safety)
      if ! sudo iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
        sudo iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
      fi
    fi

    # 4) Ensure nftables accept policy exists (idempotent; no flushes)
    if command -v nft >/dev/null 2>&1; then
      sudo nft add table inet filter 2>/dev/null || true
      sudo nft add chain inet filter input   "{ type filter hook input priority 0; policy accept; }" 2>/dev/null \
        || sudo nft chain inet filter input "{ policy accept; }"
    fi

    # 5) Final: prove the port is open locally
    echo "🧪 Local connect test:"
    timeout 3 bash -lc "nc -zvw2 127.0.0.1 6443" && echo "✅ localhost:6443 open" || echo "❌ localhost:6443 closed"
  '
}

# === Node prep ==================================================
update_node() {
  local h=$1
  run_remote "$h" '
    sudo apt-get update -y
    sudo apt-mark unhold kubeadm kubelet kubectl >/dev/null 2>&1 || true
    sudo apt-get -o Dpkg::Options::="--force-confold" -y upgrade || true
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release jq iproute2 iputils-ping traceroute arptables ebtables nftables conntrack
  '
}

configure_crictl() {
  local h=$1
  run_remote "$h" "
    sudo tee /etc/crictl.yaml >/dev/null <<'YAML'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
pull-image-on-create: false
YAML
  "
}

install_containerd() {
  local h=$1
  run_remote "$h" "
    sudo apt-get install -y containerd cri-tools
    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    # pin pause image to match kubeadm recommendation
    sudo sed -i \"s|^[[:space:]]*sandbox_image = \\\".*\\\"|    sandbox_image = \\\"registry.k8s.io/pause:3.10.1\\\"|\" /etc/containerd/config.toml
    sudo systemctl enable --now containerd
    sudo systemctl restart containerd || true
    sudo systemctl restart kubelet || true
  "
  # ← now call the local helper from the local shell
  configure_crictl "$h"
}

install_k8s_pkgs() {
  local h=$1
  run_remote "$h" "
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION%.*}/deb/Release.key \
      | sudo gpg --dearmor --yes --batch -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION%.*}/deb/ /' \
      | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y kubelet=${K8S_VERSION}-1.1 kubeadm=${K8S_VERSION}-1.1 kubectl=${K8S_VERSION}-1.1
    sudo systemctl enable kubelet
  "
}

cleanup_lxd() {
  local h=$1
  run_remote "$h" '
    echo "🧹 Removing LXD/LXC remnants..."
    sudo systemctl stop snap.lxd.daemon lxd lxcfs 2>/dev/null || true
    sudo snap remove lxd 2>/dev/null || true
    ip link show lxdbr0 >/dev/null 2>&1 && sudo ip link del lxdbr0 || true
    ip -o link | awk -F": " "/^(lxc|lxcb|lxd)/{print \$2}" | cut -d@ -f1 | \
      xargs -r -I{} sudo ip link del {} 2>/dev/null || true
    ip rule | awk "/lxd|lxc/ {system(\"sudo ip rule del \" \$0)}" || true
  '
}

tune_sysctl() {
  local h=$1
  run_remote "$h" '
    echo br_netfilter | sudo tee /etc/modules-load.d/br_netfilter.conf
    sudo modprobe br_netfilter || true
    sudo tee /etc/sysctl.d/99-k8s.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.enp0s6.rp_filter = 0
fs.inotify.max_user_watches = 1048576
fs.inotify.max_user_instances = 1024
EOF
    # Apply each file atomically; -e ignores unknown/unsupported keys
    for f in /etc/sysctl.d/*.conf; do
      sudo sysctl -e -p "$f" >/dev/null || true
    done
    sudo swapoff -a
    sudo sed -i "/[[:space:]]swap[[:space:]]/s/^/#/" /etc/fstab
  '
}

ensure_kubelet_open() {
  local h=$1
  run_remote "$h" '
    # iptables: allow kubelet
    if command -v iptables >/dev/null 2>&1; then
      if ! sudo iptables -C INPUT -p tcp --dport 10250 -j ACCEPT 2>/dev/null; then
        echo "🔓 Allowing TCP/10250 in iptables (INPUT)…"
        sudo iptables -I INPUT 1 -p tcp --dport 10250 -j ACCEPT || true
      fi
      if ! sudo iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
        sudo iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
      fi
    fi
    # nft fallback (accept policy) — safe/idempotent
    if command -v nft >/dev/null 2>&1; then
      sudo nft add table inet filter 2>/dev/null || true
      sudo nft add chain inet filter input "{ type filter hook input priority 0; policy accept; }" 2>/dev/null \
        || sudo nft chain inet filter input "{ policy accept; }"
    fi
  '
}

purge_old_calico() {
  local h=$1
  run_remote "$h" '
    set -euo pipefail
    # Remove lingering Calico/VXLAN links if they exist (idempotent)
    for dev in vxlan.calico tunl0; do
      ip link show "$dev" >/dev/null 2>&1 && sudo ip link del "$dev" || true
    done
    # Remove cali* veth pairs
    ip -o link | awk -F": " "/^[0-9]+: cali/{print \$2}" | cut -d@ -f1 | \
      xargs -r -I{} sudo ip link del {} 2>/dev/null || true

    # Clean Calico iptables chains only (leave KUBE-* and OCI policy alone)
    for table in filter nat mangle raw; do
      if sudo iptables -t "$table" -S 2>/dev/null | grep -qE "^-N cali"; then
        sudo iptables -t "$table" -S | awk "/^-N cali/ {print \$2}" | while read -r CH; do
          # Delete rules referencing the chain, then delete the chain itself
          sudo iptables -t "$table" -S | grep " $CH " | sed "s/^-A/sudo iptables -t $table -D/" | bash || true
          sudo iptables -t "$table" -F "$CH" 2>/dev/null || true
          sudo iptables -t "$table" -X "$CH" 2>/dev/null || true
        done
      fi
    done
  '
}

purge_old_cilium() {
  local h=$1
  run_remote "$h" '
    set -euo pipefail
    echo "🧹 Purging old Cilium state..."

    # 0) Try uninstalling via CLI if possible
    kubectl -n kube-system get ds cilium >/dev/null 2>&1 && cilium uninstall --wait || true
    kubectl -n kube-system delete cm cilium-config >/dev/null 2>&1 || true
    kubectl -n kube-system delete sa,clusterrole,clusterrolebinding -l k8s-app=cilium >/dev/null 2>&1 || true

    # 1) Unmount BPF and Cilium cgroup mounts
    mountpoint -q /sys/fs/bpf && sudo umount -l /sys/fs/bpf || true
    mountpoint -q /var/run/cilium/cgroupv2 && sudo umount -l /var/run/cilium/cgroupv2 || true

    # 2) Delete leftover links
    for dev in cilium_host cilium_net cilium_vxlan; do
      ip link show "$dev" >/dev/null 2>&1 && sudo ip link del "$dev" || true
    done

    # 3) Clean iptables CILIUM-* chains
    for table in filter nat; do
      sudo iptables -t "$table" -S 2>/dev/null | awk "/^-N CILIUM/ {print \$2}" | \
      while read -r CH; do
        sudo iptables -t "$table" -F "$CH" 2>/dev/null || true
        sudo iptables -t "$table" -X "$CH" 2>/dev/null || true
      done
    done

    # 4) Delete on-disk state
    sudo rm -rf /var/run/cilium /var/lib/cilium
  '
}

# === Deep CNI cleanup (network-safe: NO firewall, NO routes, NO ip rules) ==
cleanup_cni_deep() {
  local h=$1
  run_remote "$h" '
    set -euo pipefail
    set -x

    # Stop kubelet and reset kubeadm state (does not touch OS networking)
    sudo systemctl stop kubelet 2>/dev/null || true
    # Remove all containers via containerd CRI (idempotent)
    ids=$(sudo crictl ps -aq 2>/dev/null || true)
    if [ -n "$ids" ]; then
      echo "$ids" | xargs -r sudo crictl rm -f >/dev/null 2>&1 || true
    fi
    sudo kubeadm reset -f || true

    # CNI configs/state on disk ONLY (leave /opt/cni/bin tools installed)
    sudo rm -rf /etc/cni/net.d /var/lib/cni /run/flannel 2>/dev/null || true

    # DO NOT touch iptables/nft/ipvs/ip rules/routes/interfaces at all.
    # (OCI policy routing is fragile and required for SSH reachability.)

    # Cilium BPF mount points may block re-install; unmount if mounted
    mountpoint -q /sys/fs/bpf && sudo umount /sys/fs/bpf || true
    sudo rm -rf /sys/fs/bpf 2>/dev/null || true
    sudo rm -rf /var/run/cilium /var/lib/cilium 2>/dev/null || true

    # Kubernetes state on disk
    sudo rm -rf /etc/kubernetes /var/lib/kubelet /var/lib/etcd 2>/dev/null || true

    # Restart container runtime & kubelet (kubelet will idle until re-init)
    sudo systemctl restart containerd 2>/dev/null || true
    sudo systemctl restart kubelet 2>/dev/null || true

    set +x
  '
}

# === OCI network sanity checks (ports, MTU, routes) ============
oci_net_doctor() {
  local h=$1
  run_remote "$h" '
    echo "🧪 OCI Net Doctor:"
    echo "• Interfaces & MTU:"
    ip -o link | awk -F": " '"'"'{print $2}'"'"' | xargs -I{} bash -c '"'"'echo -n {}: ; ip link show {} | awk '"'"'"'"'/mtu/{print \$5}'"'"'"'"''"'"'
    echo "• Default route:"; ip route show default || true
    echo "• rp_filter:"; sysctl net.ipv4.conf.all.rp_filter net.ipv4.conf.default.rp_filter
    echo "• Required ports (should be reachable intra-VCN): 6443/tcp, 10250/tcp, 53/udp"
  '
}

# === Control plane init (NO CNI yet) ===========================
init_master() {
  run_remote_stream "$MASTER_NODE" "
    sudo kubeadm init \
      --kubernetes-version=v${K8S_VERSION} \
      --pod-network-cidr=${POD_CIDR} \
      --service-cidr=${SERVICE_CIDR} \
      --apiserver-advertise-address=\$(hostname -I | awk '{print \$1}') \
      --ignore-preflight-errors=NumCPU

    mkdir -p \$HOME/.kube
    sudo install -o \$USER -g \$USER -m 0644 /etc/kubernetes/admin.conf \$HOME/.kube/config

    echo '⏳ Waiting API health...'
    until curl -ks https://localhost:6443/healthz | grep -q '^ok$'; do sleep 3; done
  "

  # Save join command
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$MASTER_NODE" \
    'kubeadm token create --print-join-command' | tr -d '\r' > join_cmd.sh
  echo "✅ Join command saved to $(pwd)/join_cmd.sh"
}

# === Cilium CLI & install ======================================
install_cilium_cli() {
  local h=$1
  local os="linux"
  local ARCH="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$h" 'uname -m' | tr -d "\r")"
  echo "🧩 Detected remote architecture: $ARCH on host $h"

  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
  esac
  run_remote "$h" "
    set -e
    curl -fsSL -o /tmp/cilium.tar.gz https://github.com/cilium/cilium-cli/releases/download/v${CILIUM_CLI_VERSION}/cilium-${os}-${ARCH}.tar.gz
    sudo tar -C /usr/local/bin -xzf /tmp/cilium.tar.gz cilium
    cilium version
  "
}

verify_no_cilium_links() {
  local h=$1
  run_remote "$h" '
    if ip -o link | grep -qE "cilium_(host|net|vxlan)"; then
      echo "❌ lingering cilium links"; ip -o link | grep cilium_;
      exit 1;
    else
      echo "✅ no cilium links";
    fi
  '
}

cilium_install_master() {
  install_cilium_cli "$MASTER_NODE"
  run_remote_stream "$MASTER_NODE" "
    set -e
    if kubectl -n kube-system get ds cilium >/dev/null 2>&1; then
      cilium uninstall --wait >/dev/null 2>&1 || true
    fi
  "
  # Install Cilium (direct routing, kube-proxy partial, BPF MASQ) + hard wait
  run_remote_stream "$MASTER_NODE" "
    set -euo pipefail
    cilium install --version v${CILIUM_VERSION} \
      --set tunnelProtocol=vxlan \
      --set kubeProxyReplacement=false \
      --set ipam.mode=kubernetes \
      --set rollOutCiliumPods=true \
      --set mtu=1450

    echo '⏳ Waiting for Cilium DaemonSet…'
    if ! kubectl -n kube-system rollout status ds/cilium --timeout=10m; then
      echo '❌ Cilium rollout timed out — dumping quick diagnostics'
      kubectl -n kube-system get pods -o wide
      kubectl -n kube-system describe ds/cilium | tail -n +1 | sed 's/^/    /'
      kubectl -n kube-system logs -l k8s-app=cilium --tail=200 --all-containers=true || true
      exit 1
    fi
    cilium status --wait --wait-duration=5m
    echo '✅ Cilium installed (v${CILIUM_VERSION})'
  "
}

# === Workers: pre-join reachability checks + join ==============
prejoin_matrix_to_master() {
  local master_ip
  master_ip=$(ssh "$MASTER_NODE" "hostname -I | awk '{print \$1}'")
  echo "🔎 Checking reachability to master ${master_ip}:6443 from workers…"
  for w in "${NODES[@]:1}"; do
    run_remote "$w" "
      sudo ip neigh flush all || true
      timeout 4 bash -lc 'nc -zvw3 ${master_ip} 6443' && echo '✅ 6443 OK' || (echo '❌ 6443 blocked'; exit 1)
      timeout 4 bash -lc 'nc -zvw3 ${master_ip} 10250' || echo '⚠️  10250 not open (fine if kubelet not bound on master)'
      ping -c1 -W2 ${master_ip} >/dev/null && echo '✅ ICMP OK' || echo '⚠️  ICMP blocked'
    "
  done
  echo "🔎 Checking reachability from master to each worker's kubelet (10250)…"
  for w in "${NODES[@]:1}"; do
    worker_ip=$(ssh "$w" "hostname -I | awk '{print \$1}'")
    run_remote "$MASTER_NODE" "timeout 4 bash -lc 'nc -zvw3 ${worker_ip} 10250' && echo '✅ ${worker_ip}:10250 OK' || echo '❌ ${worker_ip}:10250 blocked'"
  done
}

join_workers() {
  local join_cmd; read -r join_cmd < join_cmd.sh
  echo "🔗 Joining workers…"
  for w in "${NODES[@]:1}"; do
    run_remote "$w" "
      sudo kubeadm reset -f || true
      sudo ${join_cmd} --ignore-preflight-errors=NumCPU
    "
  done
}

# === Post-setup: inter-node/pod connectivity matrix ============
deploy_netshoot_daemonset() {
  run_remote "$MASTER_NODE" "
    cat <<'YAML' | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: netshoot
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: netshoot
  template:
    metadata:
      labels:
        app: netshoot
    spec:
      hostNetwork: false
      containers:
      - name: netshoot
        image: nicolaka/netshoot:latest
        command: ['sleep','infinity']
        securityContext:
          capabilities:
            add: ['NET_ADMIN','NET_RAW']
YAML
    kubectl -n kube-system rollout status ds/netshoot --timeout=120s
  "
}

matrix_checks() {
  echo "🧪 Inter-node & inter-pod connectivity matrix"
  run_remote "$MASTER_NODE" '
    set -e
    nodes=($(kubectl get nodes -o jsonpath="{.items[*].status.addresses[?(@.type==\"InternalIP\")].address}"))
    pods=($(kubectl -n kube-system get pods -l app=netshoot -o jsonpath="{.items[*].metadata.name}"))
    ns=kube-system

    echo "Nodes: ${nodes[*]}"
    echo "Pods:  ${pods[*]}"

    echo "→ Node-to-Node: ICMP + TCP 6443/10250"
    for a in "${nodes[@]}"; do
      for b in "${nodes[@]}"; do
        [ "$a" = "$b" ] && continue
        printf "  %s -> %s : " "$a" "$b"
        ok=1
        timeout 3 ping -c1 -W2 "$b" >/dev/null || ok=0
        timeout 3 bash -lc "nc -zvw2 $b 6443" >/dev/null 2>&1 || true
        timeout 3 bash -lc "nc -zvw2 $b 10250" >/dev/null 2>&1 || true
        [ $ok -eq 1 ] && echo "OK" || echo "ping-fail"
      done
    done

    echo "→ Pod-to-ClusterIP DNS test (CoreDNS)"
    svcip=$(kubectl get svc kube-dns -n kube-system -o jsonpath="{.spec.clusterIP}")
    for p in "${pods[@]}"; do
      kubectl -n "$ns" exec "$p" -- sh -c "timeout 3 nc -zvw2 $svcip 53" && echo "  $p -> $svcip:53 OK" || echo "  $p -> $svcip:53 FAIL"
    done

    echo "→ Pod-to-Pod (same DS), curl to Kubernetes service (10.96.0.1:443)"
    for p in "${pods[@]}"; do
      kubectl -n "$ns" exec "$p" -- sh -c "timeout 5 curl -skf https://10.96.0.1:443 >/dev/null" \
        && echo "  $p -> 10.96.0.1:443 OK" || echo "  $p -> 10.96.0.1:443 FAIL"
    done
  '
}

# === Verification & report =====================================
verify_cluster() {
  ssh "$MASTER_NODE" bash -s <<'EOF'
    echo "------------------------------------------------------------"
    echo "📋 Nodes:"; kubectl get nodes -o wide
    echo "------------------------------------------------------------"
    echo "📦 kube-system Pods:"; kubectl get pods -n kube-system -o wide
    echo "------------------------------------------------------------"
    echo "🧠 Cilium status:"; cilium status || true
    echo "------------------------------------------------------------"
    if kubectl get nodes | grep -q "NotReady"; then
      echo "❌ Some nodes are NotReady"; exit 1
    fi
    echo "✅ Cluster looks healthy."
EOF

  REPORT="cluster_report_$(date +%Y%m%d_%H%M%S).md"
  {
    echo "# Kubernetes Cluster Report — $(date)"
    echo "## Control Plane: $MASTER_NODE"
    echo "### Nodes"; echo '```'; ssh "$MASTER_NODE" kubectl get nodes -o wide; echo '```'
    echo "### kube-system pods"; echo '```'; ssh "$MASTER_NODE" kubectl get pods -n kube-system -o wide; echo '```'
    echo "### Cilium status"; echo '```'; ssh "$MASTER_NODE" cilium status || true; echo '```'
  } > "$REPORT"
  echo "✅ Markdown report saved: $REPORT"
}

# === Reset all nodes (detached) ================================
reset_cluster() {
  echo "🧹 Resetting all nodes…"
  for n in "${NODES[@]}"; do
    run_remote "$n" "nohup bash -lc '
      sudo systemctl stop kubelet containerd 2>/dev/null || true
      sudo kubeadm reset -f >/dev/null 2>&1 || true
      sudo rm -rf /etc/cni/net.d /var/lib/cni /var/lib/kubelet /etc/kubernetes /var/lib/etcd /run/flannel /opt/cni /var/run/cilium /var/lib/cilium
      for t in filter nat mangle raw; do iptables -t \$t -F 2>/dev/null || true; iptables -t \$t -X 2>/dev/null || true; done
      ipvsadm --clear 2>/dev/null || true
      nft flush ruleset 2>/dev/null || true
      systemctl start containerd 2>/dev/null || true
      echo done > /tmp/reset_done
    ' >/dev/null 2>&1 &"
  done
  sleep 30
  for n in "${NODES[@]}"; do run_remote "$n" 'test -f /tmp/reset_done && echo "✅ reset ok" || echo "❌ reset pending"'; done
}

# === MAIN ======================================================
case "${1:-}" in
  reset) reset_cluster; exit 0 ;;
esac

echo "⚙️  Preparing nodes (safe sequential mode)…"
for n in "${NODES[@]}"; do
  echo "——— $n ———"
  update_node "$n"
  cleanup_lxd "$n"
  tune_sysctl "$n"
  ensure_kubelet_open "$n"
  install_containerd "$n"
  install_k8s_pkgs "$n"
  oci_net_doctor "$n"
  cleanup_cni_deep "$n"
  purge_old_calico "$n"
  purge_old_cilium "$n"
  verify_no_cilium_links "$n"
  run_remote "$n" 'ip -o link | grep -E "cilium_(host|net|vxlan)" || echo "✅ no cilium links"'
done
echo "✅ Prep + deep cleanup done."

init_master
ensure_apiserver_open "$MASTER_NODE"
prejoin_matrix_to_master
join_workers

echo "🔒 Holding kube packages…"
for n in "${NODES[@]}"; do
  run_remote "$n" "sudo apt-mark hold kubelet kubeadm kubectl >/dev/null && ver=\$(kubelet --version) && echo \"[$n] held at \$ver\""
done

cilium_install_master
deploy_netshoot_daemonset
matrix_checks
verify_cluster

cat <<'TIP'

🎯 Tips (OCI):
- Ensure your VCN Security List / NSG allows **intra-VCN**:
  • TCP 6443 (API), TCP 10250 (kubelet), UDP 53 (CoreDNS)
  • (No VXLAN needed for Cilium direct routing)
- If you see intermittent drops, align MTU across nodes or set:
    cilium install ... --set mtu=1500
  (or lower if your OCI path MTU requires)

Done. Enjoy your clean Cilium-powered cluster. 🚀
TIP
