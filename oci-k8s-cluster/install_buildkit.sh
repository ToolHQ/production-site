#!/usr/bin/env bash
set -euo pipefail

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

  # --- PAM + systemd-logind fix (Ubuntu 22.04 ARM64/AMD64) -------------------
  # Ensure PAM modules exist and are linked for systemd --user compatibility
  run_remote "$h" "
    if [ -d /usr/lib/aarch64-linux-gnu/security ]; then
      if ! ls /lib/security/pam_unix.so >/dev/null 2>&1; then
        sudo mkdir -p /lib/security
        sudo ln -sf /usr/lib/aarch64-linux-gnu/security/pam_*.so /lib/security/
        echo '🔗 Linked PAM modules from /usr/lib/aarch64-linux-gnu/security to /lib/security/'
      fi
    fi

    if ! systemctl is-active --quiet systemd-logind; then
      echo '⚙️ Restarting systemd-logind...'
      sudo systemctl restart systemd-logind || true
    fi
  "

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
  echo "[$h] STEP 7: generating systemd user service for BuildKit..."
  run_remote_stream "$h" "bash -euxo pipefail <<'EOF'
set -euo pipefail

# Create systemd user service directory
mkdir -p /home/ubuntu/.config/systemd/user

# Write the systemd service unit
cat > /home/ubuntu/.config/systemd/user/buildkit.service << 'SERVICE'
[Unit]
Description=BuildKit (Rootless)
Documentation=https://github.com/moby/buildkit

[Service]
Environment="PATH=/home/ubuntu/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=/usr/local/bin/rootlesskit \
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

# Restart policy
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
SERVICE

chown ubuntu:ubuntu /home/ubuntu/.config/systemd/user/buildkit.service
chmod 0644 /home/ubuntu/.config/systemd/user/buildkit.service

echo '✅ Systemd service unit created'
EOF"
}
###############################################################################
# 8. ENABLE SERVICE
###############################################################################
bk_start_rootless_buildkit() {
  local h="$1"
  echo "[$h] STEP 8: enabling and starting BuildKit systemd user service..."
  run_remote_stream "$h" 'bash -euxo pipefail <<'\''EOF'\''
set -euo pipefail

# Ensure XDG_RUNTIME_DIR exists and has correct ownership
USER_UID=$(id -u ubuntu)
export XDG_RUNTIME_DIR=/run/user/$USER_UID
sudo mkdir -p "$XDG_RUNTIME_DIR"
sudo chown ubuntu:ubuntu "$XDG_RUNTIME_DIR"
sudo chmod 700 "$XDG_RUNTIME_DIR"

# Enable linger so user services persist
sudo loginctl enable-linger ubuntu || true

# Wait a moment for linger to take effect
sleep 3

# 🧩 Verificar e atualizar systemd/dbus se necessário
echo "🧩 Verificando versão do systemd..."
SYS_VER=$(systemctl --version 2>/dev/null | awk '/systemd/{print \$2}' || echo 0)

if [ "$SYS_VER" -lt 247 ]; then
  echo "⚙️  Atualizando systemd e dependências (versão atual: $SYS_VER)..."
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" \
       -o Dpkg::Options::="--force-confold" \
       systemd dbus-user-session systemd-container >/dev/null

  echo "✅ Pacotes atualizados. Reiniciando systemd..."
  sudo systemctl daemon-reexec || true

  echo "🔁 Agendando reboot seguro para aplicar atualizações..."
  # Cria marcador de retomada
  FLAG_FILE="/tmp/post_reboot_buildkit.flag"
  echo "resume_buildkit" | sudo tee "$FLAG_FILE" >/dev/null

  # Copia script mínimo de retomada para /usr/local/sbin
  sudo tee /usr/local/sbin/resume_buildkit.sh >/dev/null <<'EOS'
#!/bin/bash
set -euo pipefail
FLAG_FILE="/tmp/post_reboot_buildkit.flag"
if [ -f "$FLAG_FILE" ]; then
  echo "🧠 Reboot detectado — retomando BuildKit rootless setup..."
  sudo rm -f "$FLAG_FILE"

  # Reexecuta o passo de ativação do BuildKit user service
  USER_UID=$(id -u ubuntu)
  export XDG_RUNTIME_DIR="/run/user/${USER_UID}"

  sudo mkdir -p "$XDG_RUNTIME_DIR"
  sudo chown ubuntu:ubuntu "$XDG_RUNTIME_DIR"
  sudo chmod 700 "$XDG_RUNTIME_DIR"

  sudo runuser -l ubuntu -c "
    XDG_RUNTIME_DIR=/run/user/${USER_UID} nohup /usr/local/bin/rootlesskit \
      --net=slirp4netns --disable-host-loopback \
      /home/ubuntu/bin/buildkitd \
        --root /home/ubuntu/.local/share/buildkit \
        --addr unix:///home/ubuntu/.local/share/buildkit/buildkitd.sock \
        --oci-worker-no-process-sandbox \
        --config /home/ubuntu/.config/buildkit/buildkitd.toml \
        >> /home/ubuntu/buildkitd.log 2>&1 &
  "
  echo "✅ BuildKit rootless reinstanciado após reboot."
fi
EOS

  sudo chmod +x /usr/local/sbin/resume_buildkit.sh

  # Adiciona execução pós-boot via cron @reboot
  (sudo crontab -l 2>/dev/null; echo "@reboot /usr/local/sbin/resume_buildkit.sh") | sudo crontab -

  echo "💡 Reboot programado: o BuildKit será restaurado automaticamente após o boot."
  sleep 2
  sudo reboot
  exit 0
else
  echo "✅ systemd versão $SYS_VER adequada — prosseguindo."
fi


# 🧩 Garantir inicialização limpa do systemd --user pós-update
USER_UID=$(id -u ubuntu)
export XDG_RUNTIME_DIR="/run/user/${USER_UID}"

sudo mkdir -p "$XDG_RUNTIME_DIR"
sudo chown ubuntu:ubuntu "$XDG_RUNTIME_DIR"
sudo chmod 700 "$XDG_RUNTIME_DIR"

# Use systemctl --machine to interact with user systemd instance
# This bypasses DBUS issues by talking directly to systemd
echo "🔄 Reloading systemd user daemon..."
sudo systemctl --machine=ubuntu@ --user daemon-reload

echo "⚙️  Enabling BuildKit service..."
sudo systemctl --machine=ubuntu@ --user enable buildkit.service

# Stop any existing buildkit service
echo "🛑 Stopping any existing BuildKit service..."
sudo systemctl --machine=ubuntu@ --user stop buildkit.service 2>/dev/null || true

# Start the buildkit service
echo "🚀 Starting BuildKit service..."
sudo systemctl --machine=ubuntu@ --user start buildkit.service

# Check service status
echo "🔍 Checking BuildKit service status..."
sudo systemctl --machine=ubuntu@ --user status buildkit.service --no-pager --lines=10 || true

echo "✅ BuildKit systemd user service started"
EOF'
}
###############################################################################
# 9. WAIT FOR SOCKET
###############################################################################
bk_wait_socket() {
  local h="$1"
  echo "[$h] STEP 9: waiting for BuildKit socket..."
  run_remote_stream "$h" 'bash -euxo pipefail <<'\''EOF'\''
set -euo pipefail
SOCK=/home/ubuntu/.local/share/buildkit/buildkitd.sock
USER_UID=$(id -u ubuntu)
export XDG_RUNTIME_DIR=/run/user/$USER_UID

echo "⏳ Waiting for BuildKit socket to appear..."
for i in {1..30}; do
  if [ -S "$SOCK" ]; then
    echo "✅ BuildKit socket detected at $SOCK"
    
    # Verify we can connect to it
    if timeout 5 /home/ubuntu/bin/buildctl --addr unix://$SOCK debug workers >/dev/null 2>&1; then
      echo "✅ BuildKit daemon is responding"
      exit 0
    else
      echo "⚠️  Socket exists but daemon not responding yet, waiting..."
    fi
  fi
  
  # Show service status on first iteration and every 10 iterations
  if [ $i -eq 1 ] || [ $((i % 10)) -eq 0 ]; then
    echo "🔍 Iteration $i: Checking service status..."
    sudo systemctl --machine=ubuntu@ --user status buildkit.service --no-pager --lines=5 2>/dev/null || true
  fi
  
  sleep 2
done

echo "❌ BuildKit socket did not appear after 60 seconds"
echo "📋 Final service status:"
sudo systemctl --machine=ubuntu@ --user status buildkit.service --no-pager --lines=20 2>/dev/null || true

echo "📋 Service journal (last 50 lines):"
sudo journalctl --machine=ubuntu@ --user -u buildkit.service -n 50 --no-pager 2>/dev/null || true

exit 1
EOF'
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
