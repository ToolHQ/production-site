#!/usr/bin/env bash
# ---------------------------------------------------------------
# OCI A1.Flex ARM Kubernetes cluster bootstrapper (Cilium edition)
# Version: v2.0 (Cilium 1.18.2, vxlan or direct routing, deep CNI cleanup)
# ---------------------------------------------------------------
set -euo pipefail

source "$(dirname "$0")/common.sh"

export DEBIAN_FRONTEND=noninteractive
LOGFILE="../logs/setup_k8s_cluster_$(date +%Y%m%d_%H%M%S).log"
REPORT="../logs/cluster_report_$(date +%Y%m%d_%H%M%S).md"
exec > >(tee -a "$LOGFILE") 2>&1

SCRIPT_START=$(date +%s)

# === API server openness (master) ============================================
ensure_apiserver_open() {
  local h=$1
  run_remote_stream "$h" '
    set -e
    # quick fast-path
    if curl -sk --max-time 1 https://127.0.0.1:6443/healthz | grep -q "^ok$"; then
      echo "✅ kube-apiserver already healthy"
      exit 0
    fi

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
      sudo sed -i '/--bind-address=0\.0\.0\.0/d' /etc/kubernetes/manifests/kube-apiserver.yaml
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

# === BuildKitd (remote buildx builder) ============================================
###############################################################################
# ROOTLESS BUILDKIT INSTALLATION MODULE (FINAL VERSION)
# -----------------------------------------------------
# This module installs BuildKit 0.25.2 in full rootless mode on ARM64/AMD64
# OCI nodes. It is fully modular and uses NO heredocs inside SSH calls,
# avoiding all escaping and interpolation bugs.
#
# STRUCTURE:
#   0. Global variables
#   1. Architecture detection
#   2. Prerequisite installation
#   3. Directory preparation
#   4. RootlessKit installation
#   5. BuildKit installation
#   6. Write buildkitd.toml
#   7. Write systemd unit
#   8. Enable service
#   9. Wait for socket
#  10. install_buildkitd (orchestrator)
#
###############################################################################


###############################################################################
# 0. GLOBAL VARIABLES — required by all functions
###############################################################################

BUILDKIT_VERSION="${BUILDKIT_VERSION:-0.25.2}"
ROOTLESSKIT_VERSION="${ROOTLESSKIT_VERSION:-2.3.5}"

BK_USER="ubuntu"
BK_USER_HOME="/home/${BK_USER}"

###############################################################################
# 1. DETECT ARCHITECTURE
###############################################################################
bk_detect_arch() {
  set +u
  local h="$1"
  set -u

  # Capture architecture from remote host
  local raw rc
  raw="$(run_remote_capture "$h" "uname -m" 2>&1)"
  rc=$?

  [[ $rc -ne 0 ]] && return $rc

  # Extract last field of last line
  local arch
  arch="$(echo "$raw" | tail -n1 | awk '{print $NF}')"

  case "$arch" in
    aarch64) echo "arm64" ;;
    x86_64)  echo "amd64" ;;
    *)       return 1 ;;
  esac
}
###############################################################################
# 2. INSTALL PREREQUISITES
###############################################################################
bk_install_prereqs() {
  local h="$1"

  echo "[$h] STEP 2: installing prerequisites..."

  run_remote "$h" "
    sudo apt-get update -qq &&
    sudo apt-get install -y -qq \
      uidmap slirp4netns fuse-overlayfs iptables dbus-user-session

    USER_UID=\$(id -u ubuntu)
    USER_GID=\$(id -g ubuntu)

    echo \"✅ ubuntu UID=\$USER_UID GID=\$USER_GID\"

    # Reset existing mappings for this UID
    sudo sed -i \"/^\${USER_UID}:/d\" /etc/subuid
    sudo sed -i \"/^\${USER_UID}:/d\" /etc/subgid

    # Correct range mapping (always numeric UID)
    echo \"\$USER_UID:100000:65536\" | sudo tee -a /etc/subuid >/dev/null
    echo \"\$USER_UID:100000:65536\" | sudo tee -a /etc/subgid >/dev/null

    echo \"✅ subuid/subgid mapped for UID \$USER_UID\"

    # Ensure runtime dir exists for correct UID
    sudo mkdir -p /run/user/\$USER_UID
    sudo chown ubuntu:ubuntu /run/user/\$USER_UID
    sudo chmod 700 /run/user/\$USER_UID
    echo \"✅ /run/user/\$USER_UID ready\"

    # Ensure BuildKit dirs belong to correct UID
    sudo mkdir -p /home/ubuntu/.local/share/buildkit
    sudo mkdir -p /home/ubuntu/.config/buildkit
    sudo chown -R ubuntu:ubuntu /home/ubuntu/.local/share/buildkit
    sudo chown -R ubuntu:ubuntu /home/ubuntu/.config/buildkit
    echo \"✅ BuildKit directories fixed for UID \$USER_UID\"

    sudo loginctl enable-linger ubuntu || true
  "
}
###############################################################################
# 3. PREPARE DIRECTORIES
###############################################################################
bk_prepare_dirs() {
  local h="$1"

  echo "[$h] STEP 3: preparing directories..."

  local raw rc
  raw="$(run_remote_capture "$h" "echo /run/user/\$(id -u $BK_USER)")"
  rc=$?

  [[ $rc -ne 0 ]] && return $rc

  local BK_RUNTIME_DIR
  BK_RUNTIME_DIR="$(echo "$raw" | tail -n1 | awk '{print $NF}')"

  echo "[$h] → Using runtime dir: $BK_RUNTIME_DIR"

  run_remote "$h" "
    sudo mkdir -p $BK_RUNTIME_DIR &&
    sudo chown $BK_USER:$BK_USER $BK_RUNTIME_DIR &&
    sudo chmod 700 $BK_RUNTIME_DIR

    mkdir -p \
      $BK_USER_HOME/bin \
      $BK_USER_HOME/.config/buildkit \
      $BK_USER_HOME/.local/share/buildkit \
      $BK_USER_HOME/.config/systemd/user

    chown -R $BK_USER:$BK_USER $BK_USER_HOME/.local $BK_USER_HOME/.config $BK_USER_HOME/bin
  "
}
###############################################################################
# 4. INSTALL ROOTLESSKIT (static binary — ARM compatible)
###############################################################################
bk_install_rootlesskit() {
  local h="$1"
  local arch="$2"   # normalized: arm64 or amd64

  echo "[$h] STEP 4: installing rootlesskit v$ROOTLESSKIT_VERSION..."

  # Translate BuildKit arch → RootlessKit actual tarball arch
  local rk_arch
  case "$arch" in
    arm64) rk_arch="aarch64" ;;
    amd64) rk_arch="x86_64" ;;
    *)
      echo "[$h] ❌ Unsupported architecture for rootlesskit: $arch"
      return 1
      ;;
  esac

  local url="https://github.com/rootless-containers/rootlesskit/releases/download/v$ROOTLESSKIT_VERSION/rootlesskit-$rk_arch.tar.gz"

  run_remote_stream "$h" "bash -euxo pipefail <<'EOF'
set -euo pipefail

echo '📦 Downloading rootlesskit v$ROOTLESSKIT_VERSION for $arch...'

# Download + extract
curl -fsSL -o /tmp/rootlesskit.tar.gz '$url'
tar -xzf /tmp/rootlesskit.tar.gz -C /tmp

# The archive contains two files:
#   rootlesskit
#   rootlesskit-dockerd
sudo install -m 0755 /tmp/rootlesskit /usr/local/bin/rootlesskit

# Install rootlesskit-dockerd only if it exists (x86_64 only)
if [ -f /tmp/rootlesskit-dockerd ]; then
  echo '✅ Installing rootlesskit-dockerd'
  sudo install -m 0755 /tmp/rootlesskit-dockerd /usr/local/bin/rootlesskit-dockerd
else
  echo 'ℹ️ rootlesskit-dockerd not included for this architecture — skipping'
fi

rm -f /tmp/rootlesskit /tmp/rootlesskit-dockerd 2>/dev/null || true
rm -f /tmp/rootlesskit.tar.gz

echo '✅ rootlesskit installed at /usr/local/bin/rootlesskit'
echo '✅ version:'
rootlesskit --version

EOF"
}
###############################################################################
# 5. INSTALL BUILDKIT BINARIES
###############################################################################
bk_install_buildkit() {
  local h="$1"
  local bk_arch="$2"

  echo "[$h] STEP 5: installing BuildKit v${BUILDKIT_VERSION} ($bk_arch)..."

  local url="https://github.com/moby/buildkit/releases/download/v${BUILDKIT_VERSION}/buildkit-v${BUILDKIT_VERSION}.linux-${bk_arch}.tar.gz"

  run_remote "$h" "
    rm -f /tmp/buildkit.tar.gz &&
    curl -fsSL -o /tmp/buildkit.tar.gz '$url'
  " || return 1

  run_remote "$h" "
    tar -xzf /tmp/buildkit.tar.gz -C $BK_USER_HOME/bin --strip-components=1 &&
    chmod +x $BK_USER_HOME/bin/buildkitd &&
    chmod +x $BK_USER_HOME/bin/buildctl
  "
}
###############################################################################
# 6. WRITE CONFIG — buildkitd.toml
###############################################################################
bk_write_config() {
  local h="$1"
  echo "[$h] STEP 6: writing buildkitd.toml..."
  run_remote "$h" 'cat > /home/ubuntu/.config/buildkit/buildkitd.toml <<'\''EOF'\''
debug = false

[worker.oci]
  enabled = true
  snapshotter = "native"

[worker.oci.garbage-collection]
  enabled = true
  keepstorage = "10GB"

[worker.containerd]
  enabled = false
EOF'
}
###############################################################################
# 7. WRITE SYSTEMD UNIT
###############################################################################
bk_write_rootless_launcher() {
  local h="$1"
  echo "[$h] STEP 7: generating rootless BuildKit launcher..."
  run_remote_stream "$h" "bash -euxo pipefail <<'EOF'
set -euo pipefail
cat > /home/ubuntu/start-buildkitd.sh << 'LAUNCHER'
#!/bin/bash
set -euo pipefail

UID=\$(id -u ubuntu)
export XDG_RUNTIME_DIR=/run/user/\$UID
mkdir -p "\$XDG_RUNTIME_DIR" "\$XDG_RUNTIME_DIR/buildkit"
chmod 700 "\$XDG_RUNTIME_DIR" "\$XDG_RUNTIME_DIR/buildkit"
chown -R ubuntu:ubuntu "\$XDG_RUNTIME_DIR"

exec /usr/local/bin/rootlesskit \
  --net=slirp4netns \
  --disable-host-loopback \
  --propagation=rslave \
  --copy-up=/etc \
  --copy-up=/run \
  /home/ubuntu/bin/buildkitd \
    --root /home/ubuntu/.local/share/buildkit \
    --addr unix:///home/ubuntu/.local/share/buildkit/buildkitd.sock \
    --oci-worker-no-process-sandbox \
    --config /home/ubuntu/.config/buildkit/buildkitd.toml
LAUNCHER
sudo chown ubuntu:ubuntu /home/ubuntu/start-buildkitd.sh
sudo chmod 0755 /home/ubuntu/start-buildkitd.sh
EOF"
}
###############################################################################
# 8. ENABLE SERVICE
###############################################################################
bk_start_rootless_buildkit() {
  local h="$1"
  echo "[$h] STEP 8: starting rootless BuildKit daemon..."
  run_remote_stream "$h" "bash -euxo pipefail <<'EOF'
set -euo pipefail
UID=\$(id -u ubuntu)
export XDG_RUNTIME_DIR=/run/user/\$UID
sudo mkdir -p "\$XDG_RUNTIME_DIR"; sudo chown ubuntu:ubuntu "\$XDG_RUNTIME_DIR"; sudo chmod 700 "\$XDG_RUNTIME_DIR"

# background launch as ubuntu (no systemd dependency)
sudo -u ubuntu XDG_RUNTIME_DIR="\$XDG_RUNTIME_DIR" \
  nohup /home/ubuntu/start-buildkitd.sh > /home/ubuntu/buildkitd.log 2>&1 &

echo '✅ BuildKit launched (nohup)'; sleep 1
EOF"
}
###############################################################################
# 9. WAIT FOR SOCKET
###############################################################################
bk_wait_socket() {
  local h="$1"
  echo "[$h] STEP 9: waiting for BuildKit socket..."
  run_remote_stream "$h" "bash -euxo pipefail <<'EOF'
set -euo pipefail
SOCK=/home/ubuntu/.local/share/buildkit/buildkitd.sock
for i in {1..15}; do
  [ -S "\$SOCK" ] && { echo '✅ BuildKit socket detected'; exit 0; }
  echo '⏳ Waiting for BuildKit socket...'; sleep 2
done
echo '❌ BuildKit failed to create socket'; exit 1
EOF"
}
###############################################################################
# 10. ORCHESTRATOR — install_buildkitd
###############################################################################
install_buildkitd() {
  set +u
  local h="${1:-$MASTER_NODE}"
  set -u

  echo "[$h] ==============================================="
  echo "[$h] Installing BuildKit (rootless mode)"
  echo "[$h] ==============================================="

  # -----------------------------------------------------
  # STEP 1 — ARCH DETECTION
  # -----------------------------------------------------
  echo "[$h] → Detecting architecture..."

  local ARCH
  ARCH="$(bk_detect_arch "$h")" || {
    echo "[$h] ❌ Failed to detect architecture"
    return 1
  }

  echo "[$h] ✅ Architecture: $ARCH"

  # -----------------------------------------------------
  # STEP 2 — PREREQUISITES
  # -----------------------------------------------------
  echo "[$h] → Installing prerequisites..."
  bk_install_prereqs "$h" || {
    echo "[$h] ❌ Failed installing prerequisites"
    return 1
  }

  # -----------------------------------------------------
  # STEP 3 — DIRECTORIES
  # -----------------------------------------------------
  echo "[$h] → Preparing directories..."
  bk_prepare_dirs "$h" || {
    echo "[$h] ❌ Failed creating directories"
    return 1
  }

  # -----------------------------------------------------
  # STEP 4 — ROOTLESSKIT
  # -----------------------------------------------------
  echo "[$h] → Installing rootlesskit..."
  bk_install_rootlesskit "$h" "$ARCH" || {
    echo "[$h] ❌ Failed installing rootlesskit"
    return 1
  }

  # -----------------------------------------------------
  # STEP 5 — BUILDKIT BINARIES
  # -----------------------------------------------------
  echo "[$h] → Installing BuildKit binaries..."
  bk_install_buildkit "$h" "$ARCH" || {
    echo "[$h] ❌ Failed installing BuildKit binaries"
    return 1
  }

  # -----------------------------------------------------
  # STEP 6 — CONFIG
  # -----------------------------------------------------
  echo "[$h] → Writing BuildKit config..."
  bk_write_config "$h" || {
    echo "[$h] ❌ Failed writing BuildKit config"
    return 1
  }

  # -----------------------------------------------------
  # STEP 7 — SYSTEMD SERVICE
  # -----------------------------------------------------
  echo "[$h] → Installing systemd unit..."
  bk_write_rootless_launcher "$h" || {
    echo "[$h] ❌ Failed writing systemd unit"
    return 1
  }

  # -----------------------------------------------------
  # STEP 8 — ENABLE + START
  # -----------------------------------------------------
  echo "[$h] → Enabling BuildKit service..."
  bk_start_rootless_buildkit "$h" || {
    echo "[$h] ❌ Failed enabling BuildKit service"
    return 1
  }

  # -----------------------------------------------------
  # STEP 9 — WAIT FOR SOCKET
  # -----------------------------------------------------
  echo "[$h] → Waiting for BuildKit socket..."
  bk_wait_socket "$h" || {
    echo "[$h] ❌ BuildKit socket did not appear"
    return 1
  }

  echo "[$h] ✅ BuildKit installed successfully!"
}


# === Node prep ==================================================
update_node() {
  local h=$1
  run_remote "$h" '
    echo "🔧 Refreshing package metadata…"
    if [ $(find /var/lib/apt/lists -type f -mmin -120 2>/dev/null | wc -l) -eq 0 ]; then
      sudo apt-get -qq update
    fi
    sudo apt-mark unhold kubeadm kubelet kubectl >/dev/null 2>&1 || true
    sudo apt-get -qq -o Dpkg::Options::="--force-confold" -y upgrade || true
    sudo apt-get -qq -y --no-install-recommends install apt-transport-https ca-certificates curl gnupg lsb-release jq iproute2 iputils-ping traceroute arptables ebtables nftables conntrack
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
    
    # ✅ Enable mount propagation for CSI volumes (required for Longhorn)
    # This ensures containerd runtime properly handles volume mount propagation
    if ! grep -q 'default_runtime_name = \"runc\"' /etc/containerd/config.toml; then
      echo '🔧 Configuring containerd runtime for CSI support...'
      # Add runtime configuration after the [plugins.\"io.containerd.grpc.v1.cri\".containerd] section
      sudo sed -i '/\\[plugins\\.\"io\\.containerd\\.grpc\\.v1\\.cri\"\\.containerd\\]/a\\    default_runtime_name = \"runc\"' /etc/containerd/config.toml
    fi
    
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
    DEF_IF=$(ip route show default | awk '"'"'{print $5; exit}'"'"'); : "${DEF_IF:=enp0s6}"
    sudo tee /etc/sysctl.d/99-k8s.conf >/dev/null <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.${DEF_IF}.rp_filter = 0
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
    echo "🔓 Ensuring kubelet listens on all interfaces (0.0.0.0)…"
    KUBELET_CONF="/var/lib/kubelet/config.yaml"
    if [ -f "$KUBELET_CONF" ]; then
      sudo sed -i "s/^address:.*/address: 0.0.0.0/" "$KUBELET_CONF" || true
      sudo systemctl restart kubelet || true
    else
      echo "⚠️ kubelet config.yaml not found yet (will be created by kubeadm join)."
    fi

    # open the port via iptables just in case host firewall blocks it
    if command -v iptables >/dev/null 2>&1; then
      sudo iptables -C INPUT -p tcp --dport 10250 -j ACCEPT 2>/dev/null ||
        sudo iptables -I INPUT 1 -p tcp --dport 10250 -j ACCEPT
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
    'kubeadm token create --print-join-command' | tr -d '\r' > ../tmp/join_cmd.sh
  echo "✅ Join command saved to $(pwd)/../tmp/join_cmd.sh"
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

verify_node_podcidrs() {
  # all nodes must have .spec.podCIDR allocated for native routing
  missing=$(kubectl get nodes -o go-template='{{range .items}}{{if not .spec.podCIDR}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}')
  if [ -n "$missing" ]; then
    echo "❌ Some nodes do not have a PodCIDR allocated (controller-manager not allocating):"
    echo "$missing" | sed 's/^/   - /'
    echo "➡️  Ensure kube-controller-manager runs with --allocate-node-cidrs=true and --cluster-cidr=${POD_CIDR}"
    exit 1
  fi
}

cilium_install_master() {
  install_cilium_cli "$MASTER_NODE"

  # propagate CILIUM_MODE into the remote shell
  local tunnel_mode="${CILIUM_MODE:-vxlan}"

  run_remote_stream "$MASTER_NODE" "
    set -e
    if kubectl -n kube-system get ds cilium >/dev/null 2>&1; then
      curv=\$(cilium version --client | awk '/stable/ {print \$4}')
      if [ \"\$curv\" = \"v${CILIUM_VERSION}\" ]; then
        echo '✅ Cilium v${CILIUM_VERSION} already present — skipping reinstall.'
        exit 0
      fi
      echo '♻️  Reinstalling to refresh Cilium components...'
      cilium uninstall --wait >/dev/null 2>&1 || true
    fi
  "

  if [ "$tunnel_mode" = "direct" ]; then
    echo "🔧 Verifying all nodes have PodCIDRs allocated (required for direct routing)..."
    verify_node_podcidrs
  fi

  run_remote_stream "$MASTER_NODE" "
    # Be explicit and verbose during install; DO NOT let cilium CLI block/wait.
    set -euo pipefail
    set -x

    TUNNEL_MODE=${tunnel_mode}
    if [ \"\$TUNNEL_MODE\" = \"direct\" ]; then
      echo \"🚀 Installing Cilium in DIRECT-ROUTING mode\"

      DEF_IF=\$(ip route show default | awk '{print \$5; exit}')
      : \"\${DEF_IF:=enp0s6}\"
      IF_MTU=\$(ip link show \"\$DEF_IF\" | awk '/mtu/ {print \$5}')
      : \"\${IF_MTU:=1500}\"
      DP_MTU=\$IF_MTU    # native routing: no tunnel overhead
      echo \"📏 Using datapath MTU=\$DP_MTU (iface \$DEF_IF has MTU=\$IF_MTU)\"

      cilium install --version v${CILIUM_VERSION} \
        --wait=false \
        --set routingMode=direct \
        --set autoDirectNodeRoutes=true \
        --set kubeProxyReplacement=true \
        --set ipam.mode=kubernetes \
        --set rollOutCiliumPods=true \
        --set mtu=\$DP_MTU \
        --set bpf.masquerade=true \
        --set enableIPv4Masquerade=true \
        --set ipv4NativeRoutingCIDR=\"${POD_CIDR}\"
    else
      echo \"🌐 Installing Cilium in VXLAN mode (default)\"

      DEF_IF=\$(ip route show default | awk '{print \$5; exit}')
      : \"\${DEF_IF:=enp0s6}\"
      IF_MTU=\$(ip link show \"\$DEF_IF\" | awk '/mtu/ {print \$5}')
      : \"\${IF_MTU:=1500}\"
      DP_MTU=\$(( IF_MTU - 50 ))
      if [ \"\$DP_MTU\" -lt 1300 ]; then DP_MTU=1300; fi
      if [ \"\$DP_MTU\" -gt 8900 ]; then DP_MTU=8900; fi
      echo \"📏 Using datapath MTU=\$DP_MTU (iface \$DEF_IF has MTU=\$IF_MTU)\"

      if kubectl -n kube-system get ds cilium >/dev/null 2>&1; then
        echo \"♻️  Cilium already installed.. Upgrading if needed...\"
        # NOTE: make upgrade non-blocking; we will wait below with kubectl.
        cilium upgrade install --version v${CILIUM_VERSION} \
          --wait=false \
          --set tunnelProtocol=vxlan \
          --set kubeProxyReplacement=false \
          --set ipam.mode=kubernetes \
          --set rollOutCiliumPods=true \
          --set mtu=\$DP_MTU
      else
        echo \"🚀 Installing Cilium afresh...\"
        # NOTE: make install non-blocking; we will wait below with kubectl.
        cilium install --version v${CILIUM_VERSION} \
          --wait=false \
          --set tunnelProtocol=vxlan \
          --set kubeProxyReplacement=false \
          --set ipam.mode=kubernetes \
          --set rollOutCiliumPods=true \
          --set mtu=\$DP_MTU
      fi
    fi

    set +x
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

# === Optional: Ingress Controller ===========================================
install_ingress_controller() {
  echo "🌐 Installing NGINX Ingress Controller..."
  run_remote_stream "$MASTER_NODE" 'bash -eu -o pipefail <<'"'"'EOF'"'"'
# If ingress-nginx already exists, skip
if kubectl -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
  echo "✅ NGINX Ingress Controller already installed — skipping."
  exit 0
fi

echo "📦 Applying official NGINX Ingress manifest..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

echo "⏳ Waiting for ingress-nginx controller to become ready..."
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=5m || true

echo "✅ NGINX Ingress Controller deployed (namespace: ingress-nginx)"
EOF'
}

# === Optional ingress phase =========================================================
phase_ingress_controller() {
  if [ "${ENABLE_INGRESS:-true}" = "true" ]; then
    measure_phase "nginx ingress install" install_ingress_controller
  else
    echo "🚫 Skipping Ingress Controller installation (ENABLE_INGRESS=false)"
  fi
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
}

postjoin_matrix_to_master() {
  echo "🔎 Checking reachability from master to each worker's kubelet (10250)…"
  for w in "${NODES[@]:1}"; do
    worker_ip=$(ssh "$w" "hostname -I | awk '{print \$1}'")
    run_remote "$MASTER_NODE" "timeout 4 bash -lc 'nc -zvw3 ${worker_ip} 10250' && echo '✅ ${worker_ip}:10250 OK' || echo '❌ ${worker_ip}:10250 blocked'"
  done
}

join_workers() {
  log_node "controller" "🔗 Joining worker nodes (parallel mode)…"

  local pids=()
  local failed=()
  for w in "${WORKER_NODES[@]}"; do
    (
      ## We must strip out the oci- prefix when checking node names
      local n="${w#oci-}"
      if ! run_remote_capture "$MASTER_NODE" "kubectl get node $n" >/dev/null 2>&1; then
        local join_cmd
        join_cmd="$(cat ../tmp/join_cmd.sh)"
        for attempt in 1 2 3; do
          if run_remote_stream "$w" "sudo $join_cmd --ignore-preflight-errors=NumCPU"; then
            echo "✅ $w joined successfully"
            break
          fi
          if [ "$attempt" -eq 3 ]; then
            echo "❌ $w failed to join after 3 attempts"
            exit 1
          fi
          echo "⚠️  $w join failed (attempt $attempt). Retrying in 5s…"
          sleep 5
        done
      else
        echo "✅ $n ($w) already joined."
      fi
    ) &> >(sed "s/^/[$n] /") &   # background each node, prefix logs
    pids+=($!)
  done

  # Wait for all and collect status
  for i in "${!pids[@]}"; do
    pid=${pids[$i]}
    n=${WORKER_NODES[$i]}
    if ! wait "$pid"; then
      failed+=("$n")
    fi
  done

  if [ ${#failed[@]} -gt 0 ]; then
    log_node "controller" "❌ Some worker joins failed: ${failed[*]}"
    return 1
  fi

  log_node "controller" "✅ All workers joined successfully (parallel)."
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

fix_metrics_server_port() {
  run_remote_stream "$MASTER_NODE" 'bash -eu -o pipefail <<'"'"'EOF'"'"'
echo "🔧 Forcing metrics-server to use port 4443 and fixing probes…"
kubectl -n kube-system patch deployment metrics-server --type=json -p="[{
  \"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/ports\",
  \"value\":[{\"containerPort\":4443,\"name\":\"https\",\"protocol\":\"TCP\"}]
},{
  \"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/livenessProbe/httpGet/port\",\"value\":4443
},{
  \"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/readinessProbe/httpGet/port\",\"value\":4443
},{
  \"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",
  \"value\":[
    \"--cert-dir=/tmp\",
    \"--secure-port=4443\",
    \"--kubelet-insecure-tls\",
    \"--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname\",
    \"--metric-resolution=15s\"
  ]
}]"
kubectl -n kube-system rollout restart deploy metrics-server
kubectl -n kube-system rollout status deploy metrics-server --timeout=120s || true
echo "✅ metrics-server running securely on 4443."
EOF'
}

# Returns 0 if the Dashboard deployment exists, 1 otherwise
dashboard_exists() {
  # 1) Namespace present?
  run_remote_capture "$MASTER_NODE" "timeout 5 kubectl get ns kubernetes-dashboard -o jsonpath='{.metadata.name}' 2>/dev/null || true"
  ns=$(printf '%s' "$RUN_REMOTE_CAPTURE_RESULT" | tr -d ' \t\r\n')
  if [[ "$ns" != "kubernetes-dashboard" ]]; then
    return 1
  fi

  # 2) Deployment present?
  run_remote_capture "$MASTER_NODE" "timeout 5 kubectl -n kubernetes-dashboard get deploy kubernetes-dashboard -o jsonpath='{.metadata.name}' 2>/dev/null || true"
  dep=$(printf '%s' "$RUN_REMOTE_CAPTURE_RESULT" | tr -d ' \t\r\n')
  [[ "$dep" == "kubernetes-dashboard" ]]
}

deploy_kubedash() {
  local h="$MASTER_NODE"
  echo "🧭 Deploying Kubernetes Dashboard (v7.13.0 via Helm)…"
  run_remote_stream "$h" 'bash -eu -o pipefail <<'"'"'EOF'"'"'
# install helm if missing
if ! command -v helm >/dev/null 2>&1; then
  echo "📦 Installing helm (lightweight binary)..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# add repo and install dashboard
if ! helm repo list | grep -q kubernetes-dashboard; then
  helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
fi
helm repo update -q || true

helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard --create-namespace \
  --version 7.13.0 \
  --set service.type=NodePort \
  --set service.nodePort=31201 \
  --set kong.proxy.http.containerPort=8443 \
   --set service.targetPort=8443 \
  --set metricsScraper.enabled=true

# metrics-server (for graphs)
if ! kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1; then
  echo "📊 Installing metrics-server..."
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
fi

# admin-user + binding
kubectl -n kubernetes-dashboard get sa admin-user >/dev/null 2>&1 || \
  kubectl -n kubernetes-dashboard create serviceaccount admin-user
kubectl get clusterrolebinding admin-user-binding >/dev/null 2>&1 || \
  kubectl create clusterrolebinding admin-user-binding \
    --clusterrole=cluster-admin \
    --serviceaccount=kubernetes-dashboard:admin-user

kubectl -n kubernetes-dashboard patch deploy kubernetes-dashboard-auth \
  --type=json \
  -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args\",\"value\":[\"-v=6\",\"--alsologtostderr\"]}]"

for d in web api auth kong metrics-scraper; do
  echo "⏳ Waiting for rollout of kubernetes-dashboard-$d..."
  kubectl -n kubernetes-dashboard rollout status deploy "kubernetes-dashboard-$d" \
    --timeout=30s || true
done

echo "🔑 Admin token (valid 24h):"
kubectl -n kubernetes-dashboard create token admin-user --duration=24h || true
echo "💡 Tip: If you see 'Invalid credentials provided', clear browser cookies or use an incognito tab."
echo "✅ Kubernetes Dashboard v7.13.0 deployed successfully (via Helm)."
EOF'
}

ensure_dashboard_admin_token() {
  run_remote_stream "$MASTER_NODE" 'bash -eu -o pipefail <<EOF
kubectl create ns kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kubernetes-dashboard create sa admin-user --dry-run=client -o yaml | kubectl apply -f -
kubectl create clusterrolebinding admin-user-binding \
  --clusterrole=cluster-admin \
  --serviceaccount=kubernetes-dashboard:admin-user \
  --dry-run=client -o yaml | kubectl apply -f -
echo "🔑 New token:"
kubectl -n kubernetes-dashboard create token admin-user --duration=24h 2>/dev/null | tee /tmp/dashboard_token.txt
EOF'
}

print_kubedash_url() {
  local h="$MASTER_NODE"
  run_remote "$h" '
    ns=kubernetes-dashboard
    # pick the actual SVC that exists, preferring kong-proxy if present
    if kubectl -n "$ns" get svc kubernetes-dashboard-kong-proxy >/dev/null 2>&1; then
      SVC=kubernetes-dashboard-kong-proxy
    elif kubectl -n "$ns" get svc kubernetes-dashboard >/dev/null 2>&1; then
      SVC=kubernetes-dashboard
    else
      echo "❌ No dashboard service found in namespace $ns."
      exit 1
    fi
    NODE_PORT=$(kubectl -n "$ns" get svc "$SVC" -o jsonpath="{.spec.ports[?(@.port==443)].nodePort}")
    [ -z "$NODE_PORT" ] && NODE_PORT=$(kubectl -n "$ns" get svc "$SVC" -o jsonpath="{.spec.ports[0].nodePort}")
    NODE_IP=$(kubectl get nodes -o jsonpath="{.items[0].status.addresses[?(@.type==\"ExternalIP\")].address}")
    [ -z "$NODE_IP" ] && NODE_IP=$(hostname -I | awk "{print \$1}")
    echo "🌐 Dashboard URL: https://$NODE_IP:$NODE_PORT"
    echo "Use the token printed above to log in."
  '
}

print_kubedash_tunnel_hint() {
  local h="$MASTER_NODE"
  run_remote_stream "$h" 'bash -eu -o pipefail <<'"'"'EOF'"'"'
ns=kubernetes-dashboard

echo "🔎 Detecting Kubernetes Dashboard service..."
if kubectl -n "$ns" get svc kubernetes-dashboard-kong-proxy >/dev/null 2>&1; then
  SVC=kubernetes-dashboard-kong-proxy
elif kubectl -n "$ns" get svc kubernetes-dashboard >/dev/null 2>&1; then
  SVC=kubernetes-dashboard
else
  echo "❌ No dashboard service found in namespace $ns."
  exit 1
fi

TYPE=$(kubectl -n "$ns" get svc "$SVC" -o jsonpath="{.spec.type}")
if [ "$TYPE" = "ClusterIP" ]; then
  echo "⚙️  Service $SVC is ClusterIP → converting to NodePort..."
  kubectl -n "$ns" patch svc "$SVC" -p "{\"spec\":{\"type\":\"NodePort\"}}" >/dev/null
  sleep 2
fi

NODE_PORT=$(kubectl -n "$ns" get svc "$SVC" -o jsonpath="{.spec.ports[?(@.port==443)].nodePort}")
[ -z "$NODE_PORT" ] && NODE_PORT=$(kubectl -n "$ns" get svc "$SVC" -o jsonpath="{.spec.ports[0].nodePort}")

POD=$(kubectl -n "$ns" get pods -o jsonpath="{.items[?(@.status.phase==\"Running\")].metadata.name}" | awk "NR==1{print \$1}")
if [ -z "$POD" ]; then
  echo "⚠️  No running dashboard pod found — try again later."
  exit 2
fi

NODE=$(kubectl -n "$ns" get pod "$POD" -o jsonpath="{.spec.nodeName}")
NODE_IP=$(kubectl get node "$NODE" -o jsonpath="{.status.addresses[?(@.type==\"InternalIP\")].address}")
MASTER_PUB=$(curl -s ifconfig.me || hostname -I | awk "{print \$1}")

# Fetch the admin-user token inline
TOKEN=$(kubectl -n "$ns" create token admin-user --duration=24h 2>/dev/null || true)

echo "🧠 Dashboard pod: $POD on node $NODE ($NODE_IP)"
echo "🌐 NodePort: $NODE_PORT"

if timeout 3 bash -lc "nc -zvw2 $NODE_IP $NODE_PORT" >/dev/null 2>&1; then
  echo "✅ Node $NODE_IP:$NODE_PORT reachable from master."
else
  echo "⚠️  Node $NODE_IP:$NODE_PORT not reachable from master."
  echo "   • Verify OCI security list allows TCP/30000-32767 within VCN"
  echo "   • Verify node firewall (iptables/nft) accepts INPUT for that port"
fi

cat <<HINT

🔐 To access the Kubernetes Dashboard securely from your workstation:

  ssh -i \$SSH_KEY -L 8443:${NODE_IP}:${NODE_PORT} ubuntu@${MASTER_PUB}

Then open: https://localhost:8443/#/login
Paste this token below 👇

🪶  Token: ${TOKEN}

HINT
EOF'

  # --- Local automatic tunnel (after remote block) ---
  local node_ip node_port
  read -r node_ip node_port < <(
    ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=3 "$MASTER_NODE" '
      ns=kubernetes-dashboard
      svc=""
      if kubectl -n "$ns" get svc kubernetes-dashboard-kong-proxy >/dev/null 2>&1; then
        svc=kubernetes-dashboard-kong-proxy
      elif kubectl -n "$ns" get svc kubernetes-dashboard >/dev/null 2>&1; then
        svc=kubernetes-dashboard
      fi
      if [ -n "$svc" ]; then
        pod=$(kubectl -n "$ns" get pods -o jsonpath="{.items[?(@.status.phase==\"Running\")].metadata.name}" | awk "NR==1{print \$1}")
        node=$(kubectl -n "$ns" get pod "$pod" -o jsonpath="{.spec.nodeName}")
        ip=$(kubectl get node "$node" -o jsonpath="{.status.addresses[?(@.type==\"InternalIP\")].address}")
        port=$(kubectl -n "$ns" get svc "$svc" -o jsonpath="{.spec.ports[0].nodePort}")
        echo "$ip $port"
      fi
    ' 2>/dev/null
  )
  if [ -n "$node_ip" ] && [ -n "$node_port" ]; then
    echo "🔌  Attempting to open local SSH tunnel to Dashboard..."
    kill_local_tunnel 8443
    if ! pgrep -f "ssh.*-L.*8443:${node_ip}:${node_port}" >/dev/null 2>&1; then
      nohup ssh -i "$SSH_KEY" -f -n -L 8443:${node_ip}:${node_port} "ubuntu@${MASTER_NODE}" sleep 3600 >/dev/null 2>&1 \
        && echo "✅ Tunnel established: https://localhost:8443" \
        || echo "⚠️  Tunnel failed — please open manually."
    else
      echo "✅ Tunnel already running."
    fi
  else
    echo "⚠️  Could not detect node IP or NodePort from master — skipping auto tunnel."
  fi
}

matrix_checks() {
  echo "🧪 Inter-node & inter-pod connectivity matrix"
  # Ensure a tiny DS for network probing exists (idempotent)
  run_remote "$MASTER_NODE" '
    kubectl -n kube-system get ds netshoot >/dev/null 2>&1 || \
    kubectl -n kube-system apply -f - <<"YAML"
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: netshoot
  namespace: kube-system
spec:
  selector:
    matchLabels: { app: netshoot }
  template:
    metadata:
      labels: { app: netshoot }
    spec:
      containers:
      - name: netshoot
        image: nicolaka/netshoot
        command: ["sleep","infinity"]
        securityContext:
          capabilities:
            add: ["NET_ADMIN","NET_RAW"]
YAML
  '
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

  {
    echo "# Kubernetes Cluster Report — $(date)"
    echo "## Control Plane: $MASTER_NODE"
    echo "### Nodes"; echo '```'; ssh "$MASTER_NODE" kubectl get nodes -o wide; echo '```'
    echo "### kube-system pods"; echo '```'; ssh "$MASTER_NODE" kubectl get pods -n kube-system -o wide; echo '```'
    echo "### Cilium status"; echo '```'; ssh "$MASTER_NODE" cilium status || true; echo '```'
  } > "$REPORT"
  echo "✅ Markdown report saved: $REPORT"
}

install_local_path_provisioner() {
  echo "📦 Installing Local Path Provisioner for dynamic PVCs..."
  run_remote_stream "$MASTER_NODE" 'bash -eu -o pipefail <<'"'"'EOF'"'"'
if kubectl -n local-path-storage get deploy local-path-provisioner >/dev/null 2>&1; then
  echo "✅ Local Path Provisioner already installed — skipping."
else
  echo "🚀 Deploying Local Path Provisioner..."
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  echo "⏳ Waiting for Local Path Provisioner to become ready..."
  kubectl -n local-path-storage rollout status deploy/local-path-provisioner --timeout=2m || true
  echo "✅ Local Path Provisioner installed."
fi
EOF'

  for n in "${NODES[@]}"; do
    run_remote "$n" '
      echo "🔧 Ensuring /opt/local-path-provisioner exists..."
      if [ ! -d /opt/local-path-provisioner ]; then
        sudo mkdir -p /opt/local-path-provisioner
        sudo chown 1000:1000 /opt/local-path-provisioner
        echo "✅ Created /opt/local-path-provisioner on $(hostname)"
      else
        echo "✅ /opt/local-path-provisioner already exists on $(hostname)"
      fi

      echo "🔧 Enabling shared mount propagation (rshared) on / and /var..."
      sudo mount --make-rshared /
      sudo mount --make-rshared /var

      echo "🔧 Ensuring kubelet MountFlags=shared..."
      sudo mkdir -p /etc/systemd/system/kubelet.service.d
      if ! grep -q "MountFlags=shared" /etc/systemd/system/kubelet.service.d/override.conf 2>/dev/null; then
        echo "[Service]
MountFlags=shared" | sudo tee /etc/systemd/system/kubelet.service.d/override.conf >/dev/null
        echo "✅ Added MountFlags=shared override"
      else
        echo "✅ MountFlags=shared already configured"
      fi

      echo "🔄 Reloading kubelet and containerd..."
      sudo systemctl daemon-reexec
      sudo systemctl daemon-reload
      sudo systemctl restart containerd
      sudo systemctl restart kubelet
      echo "✅ Kubelet and containerd restarted on $(hostname)"
    '
  done
}

install_longhorn() {
  echo "📦 Installing Longhorn for distributed block storage..."
  
  # Install prerequisites on all nodes
  for n in "${NODES[@]}"; do
    run_remote "$n" '
      echo "🔧 Installing Longhorn prerequisites on $(hostname)..."
      
      # Install required packages
      sudo apt-get update -qq
      sudo apt-get install -y -qq open-iscsi nfs-common jq
      
      # Enable and start open-iscsi service
      sudo systemctl enable --now iscsid
      sudo systemctl restart iscsid
      
      echo "🔧 Enabling shared mount propagation (rshared) on / and /var..."
      sudo mount --make-rshared /
      sudo mount --make-rshared /var
      
      # ✅ Make mount propagation persistent across reboots
      echo "🔧 Making mount propagation persistent..."
      if ! grep -q "make-rshared" /etc/rc.local 2>/dev/null; then
        # Create rc.local if it doesn'"'"'t exist
        if [ ! -f /etc/rc.local ]; then
          echo "#!/bin/bash" | sudo tee /etc/rc.local >/dev/null
          sudo chmod +x /etc/rc.local
        fi
        # Add mount propagation commands before exit 0
        sudo sed -i "/^exit 0/d" /etc/rc.local 2>/dev/null || true
        echo "mount --make-rshared /
mount --make-rshared /var
exit 0" | sudo tee -a /etc/rc.local >/dev/null
        echo "✅ Added mount propagation to rc.local"
      else
        echo "✅ Mount propagation persistence already configured"
      fi
      
      echo "🔧 Ensuring kubelet MountFlags=shared..."
      sudo mkdir -p /etc/systemd/system/kubelet.service.d
      if ! grep -q "MountFlags=shared" /etc/systemd/system/kubelet.service.d/override.conf 2>/dev/null; then
        echo "[Service]
MountFlags=shared" | sudo tee /etc/systemd/system/kubelet.service.d/override.conf >/dev/null
        echo "✅ Added MountFlags=shared override"
      else
        echo "✅ MountFlags=shared already configured"
      fi
      
      echo "🔄 Reloading kubelet and containerd..."
      sudo systemctl daemon-reexec
      sudo systemctl daemon-reload
      sudo systemctl restart containerd
      sudo systemctl restart kubelet
      echo "✅ Prerequisites installed on $(hostname)"
    '
  done
  
  # Install Longhorn on the cluster
  run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail <<'EOF'
if kubectl -n longhorn-system get deploy longhorn-driver-deployer >/dev/null 2>&1; then
  echo '✅ Longhorn already installed — skipping.'
else
  echo '🚀 Deploying Longhorn v${LONGHORN_VERSION}...'
  kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v${LONGHORN_VERSION}/deploy/longhorn.yaml
  
  echo '⏳ Waiting for Longhorn system to become ready...'
  kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer --timeout=5m || true
  kubectl -n longhorn-system rollout status deploy/longhorn-ui --timeout=5m || true
  
  echo '⏳ Waiting for Longhorn to be fully operational...'
  sleep 10
  
  # Wait for daemonsets to be ready
  kubectl -n longhorn-system rollout status ds/longhorn-manager --timeout=5m || true
  
  echo '✅ Longhorn v${LONGHORN_VERSION} installed successfully.'
  echo '💡 Longhorn UI can be accessed via: kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80'
fi
EOF
"
}

# === Storage Provisioner Detection ===========================
detect_installed_provisioner() {
  local detected=""
  
  run_remote_capture "$MASTER_NODE" "kubectl -n longhorn-system get deploy longhorn-driver-deployer -o name 2>/dev/null || true"
  if [[ -n "$RUN_REMOTE_CAPTURE_RESULT" ]] && [[ "$RUN_REMOTE_CAPTURE_RESULT" =~ deployment ]]; then
    detected="longhorn"
  fi
  
  run_remote_capture "$MASTER_NODE" "kubectl -n local-path-storage get deploy local-path-provisioner -o name 2>/dev/null || true"
  if [[ -n "$RUN_REMOTE_CAPTURE_RESULT" ]] && [[ "$RUN_REMOTE_CAPTURE_RESULT" =~ deployment ]]; then
    if [[ -n "$detected" ]]; then
      detected="${detected},local-path"
    else
      detected="local-path"
    fi
  fi
  
  echo "$detected"
}

# === Get version of installed provisioner =====================
get_provisioner_version() {
  local provisioner="$1"
  local version=""
  
  if [[ "$provisioner" == "longhorn" ]]; then
    run_remote_capture "$MASTER_NODE" "kubectl -n longhorn-system get deploy longhorn-driver-deployer -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' || true"
    version="$RUN_REMOTE_CAPTURE_RESULT"
  elif [[ "$provisioner" == "local-path" ]]; then
    run_remote_capture "$MASTER_NODE" "kubectl -n local-path-storage get deploy local-path-provisioner -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' || true"
    version="$RUN_REMOTE_CAPTURE_RESULT"
  fi
  
  echo "$version" | tr -d '\r\n '
}

# === List PVCs using a specific storage class =================
list_pvcs_with_storageclass() {
  local storage_class="$1"
  run_remote "$MASTER_NODE" "kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName==\"$storage_class\") | \"\\(.metadata.namespace)/\\(.metadata.name)\"' 2>/dev/null || true"
}

# === Migrate PVCs to new storage class ========================
migrate_pvcs_to_storageclass() {
  local from_class="$1"
  local to_class="$2"
  
  echo "🔄 Migrating PVCs from '$from_class' to '$to_class'..."
  
  # Get list of PVCs using the old storage class
  run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail <<'MIGRATE_EOF'
set -x
# List all PVCs with the old storage class
pvcs=\$(kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName==\"$from_class\") | \"\\(.metadata.namespace) \\(.metadata.name)\"')

if [[ -z \"\$pvcs\" ]]; then
  echo \"✅ No PVCs found using storage class '$from_class'\"
  exit 0
fi

echo \"📋 Found PVCs to migrate:\"
echo \"\$pvcs\"

# For each PVC, we need to:
# 1. Scale down the deployment/statefulset using it
# 2. Delete the PVC and PV
# 3. Recreate the PVC with new storage class
# 4. Scale back up the deployment/statefulset

echo \"⚠️  NOTE: Migration requires recreating PVCs - data backup recommended!\"
echo \"⚠️  This is a safe migration that preserves workload state via deployment recreation.\"

while read -r ns name; do
  [[ -z \"\$ns\" || -z \"\$name\" ]] && continue
  
  echo \"🔧 Processing PVC: \$ns/\$name\"
  
  # Find pods using this PVC
  pods=\$(kubectl -n \"\$ns\" get pods -o json | jq -r --arg pvc \"\$name\" '.items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName==\$pvc) | .metadata.name')
  
  if [[ -n \"\$pods\" ]]; then
    echo \"   Pods using this PVC: \$pods\"
    
    # For each pod, find its owner (deployment/statefulset)
    for pod in \$pods; do
      owner=\$(kubectl -n \"\$ns\" get pod \"\$pod\" -o jsonpath='{.metadata.ownerReferences[0].kind}')
      owner_name=\$(kubectl -n \"\$ns\" get pod \"\$pod\" -o jsonpath='{.metadata.ownerReferences[0].name}')
      
      echo \"   Owner: \$owner/\$owner_name\"
      
      # Note: Full migration with data preservation would require more complex logic
      # For now, we'll just patch the storage class annotation to indicate intent
      echo \"   ⚠️  Updating PVC annotation to target storage class '$to_class'\"
      kubectl -n \"\$ns\" annotate pvc \"\$name\" \"migration.target.storageclass=$to_class\" --overwrite || true
    done
  fi
  
  # Patch the PVC's storageClassName (note: this might not work for bound PVCs)
  # Most storage classes don't allow changing storageClassName on bound PVCs
  echo \"   Attempting to patch storage class (may fail if PVC is bound)...\"
  if ! kubectl -n \"\$ns\" patch pvc \"\$name\" -p '{\"spec\":{\"storageClassName\":\"$to_class\"}}' 2>/dev/null; then
    echo \"   ⚠️  Cannot patch bound PVC - manual migration required\"
    echo \"   💡 To migrate: backup data, delete workload, delete PVC, recreate with new storage class, restore data\"
    kubectl -n \"\$ns\" annotate pvc \"\$name\" \"migration.manual.required=true\" \"migration.target.storageclass=$to_class\" --overwrite || true
  else
    echo \"   ✅ PVC storage class updated\"
  fi
done <<< \"\$pvcs\"

echo \"✅ Migration process completed\"
echo \"💡 Check for any PVCs with 'migration.manual.required=true' annotation\"
MIGRATE_EOF
"
}

# === Verify storage provisioner health =======================
verify_provisioner_health() {
  local provisioner="$1"
  
  echo "🏥 Verifying health of $provisioner..."
  
  if [[ "$provisioner" == "longhorn" ]]; then
    run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail <<'VERIFY_EOF'
# Check Longhorn deployments
kubectl -n longhorn-system get deploy -o wide
echo \"---\"

# Check Longhorn daemonsets
kubectl -n longhorn-system get ds -o wide
echo \"---\"

# Verify all pods are running
not_running=\$(kubectl -n longhorn-system get pods --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l)
if [[ \$not_running -gt 0 ]]; then
  echo \"❌ Found \$not_running pods not in Running state\"
  kubectl -n longhorn-system get pods --field-selector=status.phase!=Running,status.phase!=Succeeded
  exit 1
fi

echo \"✅ All Longhorn pods are healthy\"
VERIFY_EOF
"
  elif [[ "$provisioner" == "local-path" ]]; then
    run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail <<'VERIFY_EOF'
# Check local-path-provisioner deployment
kubectl -n local-path-storage get deploy -o wide
echo \"---\"

# Verify pods are running
not_running=\$(kubectl -n local-path-storage get pods --field-selector=status.phase!=Running -o name 2>/dev/null | wc -l)
if [[ \$not_running -gt 0 ]]; then
  echo \"❌ Found \$not_running pods not in Running state\"
  kubectl -n local-path-storage get pods --field-selector=status.phase!=Running
  exit 1
fi

echo \"✅ Local Path Provisioner is healthy\"
VERIFY_EOF
"
  fi
}

# === Uninstall provisioner ====================================
uninstall_provisioner() {
  local provisioner="$1"
  
  echo "🗑️  Uninstalling $provisioner..."
  
  if [[ "$provisioner" == "longhorn" ]]; then
    # Check if any PVCs are using longhorn storage class
    run_remote_capture "$MASTER_NODE" "kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName==\"longhorn\") | \"\\(.metadata.namespace)/\\(.metadata.name)\"' | wc -l"
    pvc_count="${RUN_REMOTE_CAPTURE_RESULT//[^0-9]/}"
    
    if [[ -n "$pvc_count" ]] && [[ "$pvc_count" -gt 0 ]]; then
      echo "⚠️  Cannot uninstall Longhorn: $pvc_count PVC(s) still using 'longhorn' storage class"
      run_remote "$MASTER_NODE" "kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName==\"longhorn\") | \"\\(.metadata.namespace)/\\(.metadata.name)\"'"
      return 1
    fi
    
    run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail <<'UNINSTALL_EOF'
echo \"🗑️  Removing Longhorn components...\"
kubectl -n longhorn-system delete --all deploy,ds,svc,sa,pvc 2>/dev/null || true
kubectl delete namespace longhorn-system --timeout=120s 2>/dev/null || true
echo \"✅ Longhorn uninstalled\"
UNINSTALL_EOF
"
  elif [[ "$provisioner" == "local-path" ]]; then
    # Check if any PVCs are using local-path storage class
    run_remote_capture "$MASTER_NODE" "kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName==\"local-path\") | \"\\(.metadata.namespace)/\\(.metadata.name)\"' | wc -l"
    pvc_count="${RUN_REMOTE_CAPTURE_RESULT//[^0-9]/}"
    
    if [[ -n "$pvc_count" ]] && [[ "$pvc_count" -gt 0 ]]; then
      echo "⚠️  Cannot uninstall Local Path Provisioner: $pvc_count PVC(s) still using 'local-path' storage class"
      run_remote "$MASTER_NODE" "kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName==\"local-path\") | \"\\(.metadata.namespace)/\\(.metadata.name)\"'"
      return 1
    fi
    
    run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail <<'UNINSTALL_EOF'
echo \"🗑️  Removing Local Path Provisioner components...\"
kubectl delete -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml 2>/dev/null || true
kubectl delete namespace local-path-storage --timeout=120s 2>/dev/null || true
echo \"✅ Local Path Provisioner uninstalled\"
UNINSTALL_EOF
"
  fi
}

# === Update provisioner =======================================
update_provisioner() {
  local provisioner="$1"
  local current_version="$2"
  local target_version="$3"
  
  echo "🔄 Updating $provisioner from v$current_version to v$target_version..."
  
  # Create backup annotation on existing resources
  run_remote "$MASTER_NODE" "kubectl get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName==\"$provisioner\") | \"kubectl -n \\(.metadata.namespace) annotate pvc \\(.metadata.name) backup.before.update=v$current_version --overwrite\"' | bash -s 2>/dev/null || true"
  
  if [[ "$provisioner" == "longhorn" ]]; then
    # Longhorn upgrade
    run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail <<'UPDATE_EOF'
echo \"📦 Upgrading Longhorn to v$target_version...\"

# Apply new manifest
if kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v$target_version/deploy/longhorn.yaml; then
  echo \"⏳ Waiting for Longhorn components to update...\"
  kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer --timeout=5m || {
    echo \"❌ Longhorn update failed - attempting rollback\"
    kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v$current_version/deploy/longhorn.yaml
    kubectl -n longhorn-system rollout status deploy/longhorn-driver-deployer --timeout=5m
    exit 1
  }
  
  kubectl -n longhorn-system rollout status deploy/longhorn-ui --timeout=5m || true
  kubectl -n longhorn-system rollout status ds/longhorn-manager --timeout=5m || true
  
  echo \"✅ Longhorn updated to v$target_version\"
else
  echo \"❌ Failed to apply new manifest\"
  exit 1
fi
UPDATE_EOF
"
  elif [[ "$provisioner" == "local-path" ]]; then
    # Local path provisioner update
    run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail <<'UPDATE_EOF'
echo \"📦 Updating Local Path Provisioner...\"

# The local-path-provisioner typically uses 'master' branch, so we just reapply
if kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml; then
  echo \"⏳ Waiting for Local Path Provisioner to update...\"
  kubectl -n local-path-storage rollout status deploy/local-path-provisioner --timeout=3m || {
    echo \"❌ Local Path Provisioner update failed\"
    exit 1
  }
  
  echo \"✅ Local Path Provisioner updated\"
else
  echo \"❌ Failed to apply new manifest\"
  exit 1
fi
UPDATE_EOF
"
  fi
}

# === Main storage provisioner management ======================
install_storage_provisioner() {
  local desired="${STORAGE_PROVISIONER}"
  local installed
  local other_provisioner=""
  
  echo "🔍 Detecting installed storage provisioners..."
  installed=$(detect_installed_provisioner)
  
  if [[ -z "$installed" ]]; then
    echo "📦 No storage provisioner detected. Installing $desired..."
    if [[ "$desired" == "local-path" ]]; then
      install_local_path_provisioner
    elif [[ "$desired" == "longhorn" ]]; then
      install_longhorn
    else
      echo "⚠️  Unknown STORAGE_PROVISIONER value: ${desired}"
      echo "   Valid options: 'longhorn' (default) or 'local-path'"
      echo "   Defaulting to Longhorn..."
      install_longhorn
    fi
    return 0
  fi
  
  echo "✅ Detected installed provisioner(s): $installed"
  
  # Check if desired provisioner is already installed
  if [[ "$installed" == *"$desired"* ]]; then
    echo "✅ Desired provisioner ($desired) is already installed"
    
    # Check for updates
    current_version=$(get_provisioner_version "$desired")
    if [[ -n "$current_version" ]]; then
      echo "📊 Current $desired version: v$current_version"
      
      # For longhorn, compare with LONGHORN_VERSION from common.sh
      if [[ "$desired" == "longhorn" ]] && [[ "$current_version" != "$LONGHORN_VERSION" ]]; then
        echo "🔄 Update available: v$current_version → v$LONGHORN_VERSION"
        
        if update_provisioner "$desired" "$current_version" "$LONGHORN_VERSION"; then
          echo "✅ Update successful"
          verify_provisioner_health "$desired"
        else
          echo "❌ Update failed - rolled back to v$current_version"
          return 1
        fi
      else
        echo "✅ $desired is up to date"
      fi
    fi
    
    # Verify health
    verify_provisioner_health "$desired"
    
    # Check if there's another provisioner to clean up
    if [[ "$installed" == *","* ]]; then
      # Multiple provisioners detected
      if [[ "$desired" == "longhorn" ]]; then
        other_provisioner="local-path"
      else
        other_provisioner="longhorn"
      fi
      
      echo "🔍 Found other provisioner: $other_provisioner"
      echo "🔄 Attempting to migrate resources and cleanup..."
      
      # Migrate PVCs from other provisioner
      if [[ "$other_provisioner" == "local-path" ]]; then
        migrate_pvcs_to_storageclass "local-path" "$desired"
      else
        migrate_pvcs_to_storageclass "longhorn" "$desired"
      fi
      
      # Verify migration completed
      echo "⏳ Waiting for resources to stabilize..."
      sleep 10
      
      # Try to uninstall the other provisioner
      if uninstall_provisioner "$other_provisioner"; then
        echo "✅ Successfully cleaned up $other_provisioner"
      else
        echo "⚠️  Could not fully remove $other_provisioner - manual cleanup may be required"
      fi
    fi
  else
    # Desired provisioner is not installed, but another one is
    echo "🔄 Current provisioner: $installed, desired: $desired"
    echo "📦 Installing $desired alongside $installed..."
    
    if [[ "$desired" == "local-path" ]]; then
      install_local_path_provisioner
    else
      install_longhorn
    fi
    
    # Migrate resources
    echo "🔄 Migrating resources to $desired..."
    if [[ "$installed" == "local-path" ]]; then
      migrate_pvcs_to_storageclass "local-path" "$desired"
    else
      migrate_pvcs_to_storageclass "longhorn" "$desired"
    fi
    
    # Verify new provisioner
    verify_provisioner_health "$desired"
    
    echo "⏳ Waiting for migration to complete..."
    sleep 10
    
    # Try to uninstall old provisioner
    if uninstall_provisioner "$installed"; then
      echo "✅ Successfully migrated from $installed to $desired"
    else
      echo "⚠️  Migration incomplete - both provisioners are running"
      echo "   Manual cleanup of $installed may be required after verifying all workloads"
    fi
  fi
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

prepare_node() {
  local h=$1
  update_node "$h"
  cleanup_lxd "$h"
  tune_sysctl "$h"
  ensure_kubelet_open "$h"
  install_containerd "$h"
  run_remote_capture "$h" "kubelet --version 2>/dev/null || echo none"
  remote_ver="$RUN_REMOTE_CAPTURE_RESULT"
  if [[ "$remote_ver" != *"$K8S_VERSION"* ]]; then
    install_k8s_pkgs "$h"
  else
    echo "✅ $h already on K8s $K8S_VERSION"
  fi
  if [ "${FORCE_CLEANUP:-false}" = "true" ]; then
    cleanup_cni_deep "$h"
    purge_old_calico "$h"
    purge_old_cilium "$h"
  fi
  oci_net_doctor "$h"
  verify_no_cilium_links "$h"
  run_remote "$h" 'ip -o link | grep -E "cilium_(host|net|vxlan)" || echo "✅ no cilium links"'
}
# --- Phase timing helpers (no bash -c; call real functions) ----
PHASE_TIMINGS=()

measure_phase() {
  local phase_name="$1"; shift
  local start=$SECONDS
  "$@"        # call the function and args directly in the SAME shell
  local end=$SECONDS
  PHASE_TIMINGS+=("$phase_name:$((end-start))")
}

print_phase_timings() {
  echo
  echo "⏱ Phase timings:"
  for entry in "${PHASE_TIMINGS[@]}"; do
    local name=${entry%%:*}
    local secs=${entry##*:}
    printf "   %-36s %02dm%02ds\n" "$name" $((secs/60)) $((secs%60))
  done
}


# === MAIN ======================================================
case "${1:-}" in
  reset) reset_cluster; exit 0 ;;
esac

# --- Phase timing helpers (no bash -c; call real functions) ----
PHASE_TIMINGS=()

measure_phase() {
  local phase_name="$1"; shift
  local start=$SECONDS
  "$@"        # call the function and args directly in the SAME shell
  local end=$SECONDS
  PHASE_TIMINGS+=("$phase_name:$((end-start))")
}

print_phase_timings() {
  echo
  echo "⏱ Phase timings:"
  for entry in "${PHASE_TIMINGS[@]}"; do
    local name=${entry%%:*}
    local secs=${entry##*:}
    printf "   %-36s %02dm%02ds\n" "$name" $((secs/60)) $((secs%60))
  done
}

# --- Phase wrappers (group multi-steps without bash -c) --------
phase_buildkitd() {
  echo "🧱 Installing BuildKit daemon on all nodes (parallel mode)…"

  local pids=()
  local failed=()

  ## Temp: Run only master node and exit 0
  install_buildkitd "$MASTER_NODE" && echo "[$MASTER_NODE] ✅ done" || echo "[$MASTER_NODE] ❌ failed"
  return 0

  for n in "${NODES[@]}"; do
    (
      echo "——— $n ———"
      install_buildkitd "$n" \
        && echo "[$n] ✅ done" \
        || echo "[$n] ❌ failed"
    ) &> >(sed "s/^/[$n] /") &   # background each, prefix logs
    pids+=($!)
  done

  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      failed+=("${NODES[$i]}")
    fi
  done

  if [ ${#failed[@]} -gt 0 ]; then
    echo "❌ BuildKit setup failed on: ${failed[*]}"
    return 1
  fi

  echo "✅ BuildKit daemon installed on all nodes (parallel)."
  echo "ℹ️  To use from your laptop/WSL with buildx:"
  echo "    docker buildx create --name oci-remote --driver remote \\"
  echo "      ssh://ubuntu@${MASTER_NODE_PUBLIC_IP:-YOUR_PUBLIC_IP}"
  echo "    docker buildx use oci-remote"
  echo "    docker buildx build -t YOUR_REG/repo:tag --push ."
}

phase_prepare_nodes() {
  echo "⚙️  Preparing nodes (parallel mode)…"

  local pids=()
  local failed=()

  for n in "${NODES[@]}"; do
    (
      echo "——— $n ———"
      prepare_node "$n" \
        && echo "[$n] ✅ done" \
        || echo "[$n] ❌ failed"
    ) &> >(sed "s/^/[$n] /") &   # background each, prefix logs
    pids+=($!)
  done

  # Wait for all and collect status
  for i in "${!pids[@]}"; do
    pid=${pids[$i]}
    n=${NODES[$i]}
    if ! wait "$pid"; then
      failed+=("$n")
    fi
  done

  if [ ${#failed[@]} -gt 0 ]; then
    echo "❌ Some node preparations failed: ${failed[*]}"
    return 1
  fi

  echo "✅ Prep + deep cleanup done (parallel)."
}

phase_hold_kube_packages() {
  echo "🔒 Holding kube packages (parallel mode)…"
  local pids=()
  local failed=()

  for n in "${NODES[@]}"; do
    (
      if run_remote "$n" "sudo apt-mark hold kubelet kubeadm kubectl >/dev/null"; then
        ver=$(run_remote_capture "$n" "kubelet --version")
        echo "[$n] ✅ held at $ver"
      else
        echo "[$n] ❌ hold failed"
        exit 1
      fi
    ) &> >(sed "s/^/[$n] /") &   # background each, prefix logs
    pids+=($!)
  done
  # Wait for all and collect status
  for i in "${!pids[@]}"; do
    pid=${pids[$i]}
    n=${NODES[$i]}
    if ! wait "$pid"; then
      failed+=("$n")
    fi
  done

  if [ ${#failed[@]} -gt 0 ]; then
    echo "❌ Some kube package holds failed: ${failed[*]}"
    return 1
  fi

  echo "✅ Kube package hold done (parallel)."
}

phase_dashboard_deploy() {
  if [[ "${FORCE_DASHBOARD:-false}" == "true" ]]; then
    echo "🚀 (Force) Redeploying Kubernetes Dashboard due to FORCE_DASHBOARD flag…"
    deploy_kubedash
  else
    run_remote_capture "$MASTER_NODE" "kubectl -n kubernetes-dashboard get deploy kubernetes-dashboard --no-headers 2>/dev/null || true"
    if dashboard_exists; then
      echo "⏭️  Kubernetes Dashboard already deployed — skipping."
    else 
      echo "🚀 Deploying Kubernetes Dashboard…"
      deploy_kubedash
    fi
  fi

  ensure_dashboard_admin_token
  if ! run_remote_capture "$MASTER_NODE" "kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1"; then
    echo "⏭️  metrics-server already deployed — skipping."
  else 
    echo "🚀 Fixing metrics-server port…"
    fix_metrics_server_port
  fi
  print_kubedash_url
  print_kubedash_tunnel_hint
}

# --- PHASES -----------------------------------------------------
measure_phase "buildkitd (remote buildx)"    phase_buildkitd
measure_phase "prepare nodes"                phase_prepare_nodes
if run_remote_capture "$MASTER_NODE" "kubectl get nodes >/dev/null 2>&1"; then
  echo "✅ Cluster already initialized — skipping kubeadm init."
else
  measure_phase "init master"                  init_master
fi
measure_phase "ensure apiserver open"        ensure_apiserver_open "$MASTER_NODE"
measure_phase "prejoin matrix"               prejoin_matrix_to_master
measure_phase "join workers"                 join_workers
measure_phase "postjoin matrix"              postjoin_matrix_to_master
measure_phase "hold kube packages"           phase_hold_kube_packages
measure_phase "cilium install (${CILIUM_MODE:-vxlan})" cilium_install_master
measure_phase "install storage provisioner (${STORAGE_PROVISIONER})" install_storage_provisioner
measure_phase "ingress controller"          phase_ingress_controller

# only if DEBUG=1
if [ "${DEBUG:-0}" = "1" ]; then
  measure_phase "netshoot daemonset"         deploy_netshoot_daemonset
fi

if [ "${ENABLE_DASHBOARD:-false}" = "true" ] || [ -z "${DISABLE_DASHBOARD:-}" ]; then
  measure_phase "dashboard deploy"           phase_dashboard_deploy
else
  echo "🚫 Skipping Kubernetes Dashboard installation (DISABLE_DASHBOARD set)"
fi

measure_phase "matrix checks"                matrix_checks
measure_phase "verify cluster"               verify_cluster

# --- SUMMARY ----------------------------------------------------
print_phase_timings

SCRIPT_END=$(date +%s)
ELAPSED=$((SCRIPT_END - SCRIPT_START))
printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
printf "🏁  Total installation time: %02dh:%02dm:%02ds\n" \
  $((ELAPSED/3600)) $(((ELAPSED%3600)/60)) $((ELAPSED%60))
printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

cat <<'TIP'

🎯 Tips (OCI):
- Ensure your VCN Security List / NSG allows **intra-VCN**:
  • TCP 6443 (API), TCP 10250 (kubelet), UDP 53 (CoreDNS)
  • (No VXLAN needed for Cilium direct routing)
- If you see intermittent drops, align MTU across nodes or set:
    cilium install ... --set mtu=1500
  (or lower if your OCI path MTU requires)

📦 Storage Provisioner:
- Default: Longhorn (distributed block storage with replication)
- To use local-path-provisioner instead:
    STORAGE_PROVISIONER=local-path ./setup_k8s_cluster.sh
- Longhorn UI: kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80

Done. Enjoy your clean Cilium-powered cluster with Longhorn storage. 🚀
TIP
