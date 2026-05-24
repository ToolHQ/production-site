#!/usr/bin/env bash
# scripts/bootstrap/install_k8s_kubeadm.sh
# Bootstrap vanilla Kubernetes (kubeadm) on a remote SSH host
#
# Recommended for: >= 2 vCPU / 4 GB RAM (Hetzner CAX21, SSDNodes, etc.)
# Architecture:    ARM64 (aarch64) and x86_64 (amd64) — auto-detected
#
# What it installs:
#   containerd     → CRI runtime (SystemdCgroup=true)
#   kubeadm init   → API server, etcd, scheduler, controller-manager
#   kubelet/kubectl → from pkgs.k8s.io (stable/v1.31)
#   Flannel CNI    → pod networking (10.244.0.0/16)
#   Security       → journal limits 200M + UFW firewall
#
# Usage (server/control-plane):
#   ./install_k8s_kubeadm.sh <ssh-host> [--name NAME] [--version TAG]
#
# Usage (worker join):
#   ./install_k8s_kubeadm.sh <ssh-host> --join-server <server-host>
#
# Options:
#   --name <cluster-name>    Context name in kubeconfig (default: k8s)
#   --version <tag>          K8s version, e.g. v1.31.0 (default: latest in channel v1.31)
#   --join-server <host>     SSH host of existing control-plane to join as worker
#   --no-hardening           Skip journal limits + UFW
#   --skip-kubeconfig        Don't download kubeconfig locally

set -euo pipefail

SSH_HOST="${1:?Usage: $0 <ssh-host> [--name NAME] [--version TAG] [--join-server HOST]}"
shift

CLUSTER_NAME="k8s"
K8S_VERSION=""       # empty = latest in stable channel v1.31
JOIN_SERVER=""       # if set → install as worker (kubeadm join)
DO_HARDENING=true
SKIP_KUBECONFIG=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)            CLUSTER_NAME="$2"; shift 2 ;;
        --version)         K8S_VERSION="$2";  shift 2 ;;
        --join-server)     JOIN_SERVER="$2";  shift 2 ;;
        --no-hardening)    DO_HARDENING=false; shift ;;
        --skip-kubeconfig) SKIP_KUBECONFIG=true; shift ;;
        *) echo "Flag desconhecida: $1" >&2; exit 1 ;;
    esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

step() { echo -e "\n${BLUE}${BOLD}[$1]${NC} $2"; }
ok()   { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
fail() { echo -e "${RED}❌ $1${NC}" >&2; exit 1; }

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1: Pre-flight
# ─────────────────────────────────────────────────────────────────────────────
step "1/5" "Pre-flight: conectividade SSH e hardware em $SSH_HOST"

ssh $SSH_OPTS "$SSH_HOST" "exit" 2>/dev/null \
    || fail "SSH falhou para $SSH_HOST. Verifique ~/.ssh/config e authorized_keys."
ok "SSH OK"

read -r REMOTE_ARCH REMOTE_OS REMOTE_RAM REMOTE_DISK REMOTE_CPU < <(
    ssh $SSH_OPTS "$SSH_HOST" \
        "echo \"\$(uname -m) \$(grep -oP '(?<=^ID=\"?).*(?=\"?)' /etc/os-release 2>/dev/null || uname -s) \$(free -m | awk '/^Mem:/{print \$2}') \$(df -BG / | awk 'NR==2{gsub(/G/,\"\",\$4); print \$4}') \$(nproc)\""
)

echo -e "  Arch:  ${BOLD}$REMOTE_ARCH${NC}  OS: ${BOLD}$REMOTE_OS${NC}"
echo -e "  CPU:   ${BOLD}${REMOTE_CPU} vCPU(s)${NC}  RAM: ${BOLD}${REMOTE_RAM} MB${NC}  Disco livre: ${BOLD}${REMOTE_DISK} GB${NC}"

# Architecture mapping (arm64 for aarch64, amd64 for x86_64)
case "$REMOTE_ARCH" in
    aarch64|arm64) PKG_ARCH="arm64" ;;
    x86_64|amd64)  PKG_ARCH="amd64" ;;
    *) fail "Arquitetura não suportada pelo installer: $REMOTE_ARCH (suportadas: aarch64, x86_64)" ;;
esac
echo -e "  Pkgs:  ${BOLD}${PKG_ARCH}${NC} (pkgs.k8s.io)"

# kubeadm control plane requires minimum 2 vCPU (enforced by kubeadm init)
if [[ -z "$JOIN_SERVER" && "$REMOTE_CPU" -lt 2 ]]; then
    fail "kubeadm control plane requer ≥ 2 vCPU (detectado: ${REMOTE_CPU}). Use k3s para máquinas com 1 vCPU."
fi
[[ "$REMOTE_RAM"  -lt 1700 ]] && fail "RAM insuficiente: ${REMOTE_RAM} MB (kubeadm mínimo: ~1700 MB; recomendado: 4 GB+)"
[[ "$REMOTE_DISK" -lt 10   ]] && fail "Disco insuficiente: ${REMOTE_DISK} GB (mínimo 10 GB livres)"
ok "Hardware verificado (${PKG_ARCH})"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Install containerd + kubeadm/kubelet/kubectl
# ─────────────────────────────────────────────────────────────────────────────
if [[ -n "$JOIN_SERVER" ]]; then
    step "2/5" "Instalando containerd + kubeadm/kubelet (worker) em $SSH_HOST (${PKG_ARCH})"
else
    step "2/5" "Instalando containerd + kubeadm/kubelet/kubectl (${PKG_ARCH}) em $SSH_HOST"
fi

ssh -t $SSH_OPTS "$SSH_HOST" "
    set -e
    export DEBIAN_FRONTEND=noninteractive
    PKG_ARCH=${PKG_ARCH}

    echo '📦 Atualizando apt e dependências base...'
    sudo apt-get update -qq
    sudo apt-get install -y -qq apt-transport-https ca-certificates curl gnupg lsb-release

    # ── containerd (via Docker repo — melhor suporte ARM64)
    if ! command -v containerd &>/dev/null; then
        echo '📦 Instalando containerd...'
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
        echo \"deb [arch=\${PKG_ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/ubuntu \
            \$(. /etc/os-release && echo \"\\\$VERSION_CODENAME\") stable\" \
            | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
        sudo apt-get update -qq
        sudo apt-get install -y -qq containerd.io
    fi

    # containerd: enable SystemdCgroup driver (required by kubelet)
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd
    echo '✅ containerd configurado (SystemdCgroup=true)'

    # ── Kernel modules required by kubeadm
    cat <<'EOF' | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter
    cat <<'EOF' | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    sudo sysctl --system -q
    echo '✅ Kernel modules e sysctl configurados'

    # ── Swap off (kubeadm requirement)
    sudo swapoff -a
    sudo sed -i '/swap/d' /etc/fstab 2>/dev/null || true
    echo '✅ Swap desativado'

    # ── kubeadm / kubelet / kubectl from pkgs.k8s.io (arm64 + amd64)
    echo '📦 Instalando kubeadm/kubelet/kubectl (pkgs.k8s.io/stable/v1.31)...'
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key \
        | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' \
        | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
    sudo systemctl enable kubelet
    echo '✅ kubeadm/kubelet/kubectl instalados e fixados na versão atual'
"
ok "Componentes instalados"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: kubeadm init OR kubeadm join
# ─────────────────────────────────────────────────────────────────────────────
if [[ -n "$JOIN_SERVER" ]]; then
    step "3/5" "Adicionando $SSH_HOST como worker → cluster em $JOIN_SERVER"

    # Generate a fresh join command on the server
    echo -e "  Obtendo join command do servidor $JOIN_SERVER..."
    JOIN_CMD=$(ssh $SSH_OPTS "$JOIN_SERVER" \
        "sudo kubeadm token create --print-join-command 2>/dev/null") \
        || fail "Não foi possível gerar join command no servidor $JOIN_SERVER"

    ssh -t $SSH_OPTS "$SSH_HOST" "
        set -e
        echo 'Executando kubeadm join...'
        sudo $JOIN_CMD
        echo '✅ Worker node adicionado ao cluster'
    "
    ok "Worker adicionado"
    SKIP_KUBECONFIG=true

else
    step "3/5" "Inicializando cluster com kubeadm (Flannel CNI, pod-cidr=10.244.0.0/16)"

    VERSION_FLAG=""
    [[ -n "$K8S_VERSION" ]] && VERSION_FLAG="--kubernetes-version=${K8S_VERSION}"
    # shellcheck disable=SC2089
    INIT_FLAGS="--pod-network-cidr=10.244.0.0/16 ${VERSION_FLAG}"

    ssh -t $SSH_OPTS "$SSH_HOST" "
        set -e
        MASTER_IP=\$(hostname -I | awk '{print \$1}')
        echo \"🚀 Inicializando control plane em \${MASTER_IP}...\"
        sudo kubeadm init \
            --pod-network-cidr=10.244.0.0/16 \
            --apiserver-advertise-address=\${MASTER_IP} \
            ${VERSION_FLAG} \
            2>&1 | tail -30

        # Setup kubectl for the remote user (so helm + kubectl work without sudo)
        mkdir -p \$HOME/.kube
        sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config
        sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
        echo '✅ kubeconfig configurado para o usuário'

        # Install Flannel CNI
        echo '📦 Instalando Flannel CNI...'
        kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
        echo '✅ Flannel instalado'

        # Taint removal: allow scheduling on control-plane (single-node clusters)
        NODE_COUNT=\$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
        if [[ \"\$NODE_COUNT\" -le 1 ]]; then
            kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
            echo '✅ Taint control-plane removida (single-node: permite pods no master)'
        fi

        # Wait for node Ready
        echo -n 'Aguardando nó Ready'
        timeout 150 bash -c '
            until kubectl get nodes 2>/dev/null | grep -q \" Ready \"; do
                sleep 4; echo -n .
            done
        ' && echo '' || { echo ''; warn 'Timeout — verifique: kubectl get nodes'; }

        echo ''
        kubectl get nodes -o wide
        echo ''
        kubectl get pods -n kube-system --no-headers | head -20
    "
    ok "Cluster kubeadm inicializado"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: Security hardening
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$DO_HARDENING" == "true" ]]; then
    step "4/5" "Aplicando hardening de segurança"

    ssh $SSH_OPTS "$SSH_HOST" "
        # ── Journal limits (T-293 lesson: 200M cap prevents iowait spikes)
        _ao() {
            local key=\$1 val=\$2 file=/etc/systemd/journald.conf
            if sudo grep -qE \"^#?\${key}=\" \"\$file\" 2>/dev/null; then
                sudo sed -i \"s|^#\\?\\(\${key}\\)=.*|\\1=\${val}|\" \"\$file\"
            else
                echo \"\${key}=\${val}\" | sudo tee -a \"\$file\" >/dev/null
            fi
        }
        _ao SystemMaxUse      200M
        _ao SystemKeepFree    500M
        _ao SystemMaxFileSize  50M
        _ao MaxRetentionSec   7day
        _ao RuntimeMaxUse      50M
        sudo systemctl restart systemd-journald
        sudo journalctl --vacuum-size=200M 2>&1 | grep -E 'Freed|freed|No archive' || true
        echo '✅ Journal limits: 200M cap + 7d retention'

        # ── UFW firewall
        # kubeadm ports: 6443 (API), 2379-2380 (etcd), 10250-10252 (kubelet/scheduler/ctrl-mgr)
        # Flannel ports: 8285/udp (UDP backend), 8472/udp (VXLAN backend)
        if command -v ufw >/dev/null 2>&1; then
            sudo ufw --force reset                      >/dev/null 2>&1
            sudo ufw default deny incoming              >/dev/null 2>&1
            sudo ufw default allow outgoing             >/dev/null 2>&1
            sudo ufw allow 22/tcp    comment SSH        >/dev/null 2>&1
            sudo ufw allow 6443/tcp  comment k8s-api    >/dev/null 2>&1
            sudo ufw allow 443/tcp   comment HTTPS      >/dev/null 2>&1
            sudo ufw allow 80/tcp    comment HTTP       >/dev/null 2>&1
            sudo ufw allow 8285/udp  comment flannel-udp   >/dev/null 2>&1
            sudo ufw allow 8472/udp  comment flannel-vxlan >/dev/null 2>&1
            sudo ufw allow 10250/tcp comment kubelet    >/dev/null 2>&1
            sudo ufw allow 10251/tcp comment scheduler  >/dev/null 2>&1
            sudo ufw allow 10252/tcp comment ctrl-mgr   >/dev/null 2>&1
            sudo ufw allow 2379:2380/tcp comment etcd   >/dev/null 2>&1
            sudo ufw --force enable                     >/dev/null 2>&1
            echo '✅ UFW: deny-all-in + allow SSH/k8s/HTTP(S)/Flannel/etcd'
            sudo ufw status numbered
        else
            echo '⚠️  ufw não encontrado — instale com: apt install ufw'
        fi
    "
    ok "Hardening aplicado"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5: Download kubeconfig locally
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SKIP_KUBECONFIG" == "false" ]]; then
    step "5/5" "Baixando kubeconfig para ~/.kube/${CLUSTER_NAME}.yaml"

    KUBE_DIR="${HOME}/.kube"
    mkdir -p "$KUBE_DIR"
    KUBE_PATH="${KUBE_DIR}/${CLUSTER_NAME}.yaml"

    # kubeadm kubeconfig already has the real IP (no 127.0.0.1 substitution needed)
    # Just rename the context from "kubernetes" to the cluster name
    ssh $SSH_OPTS "$SSH_HOST" \
        "cat \$HOME/.kube/config 2>/dev/null || sudo cat /etc/kubernetes/admin.conf" \
        | sed "s/: kubernetes$/: ${CLUSTER_NAME}/g" \
        | sed "s/: kubernetes-admin$/: ${CLUSTER_NAME}-admin/g" \
        > "$KUBE_PATH"
    chmod 600 "$KUBE_PATH"
    ok "Kubeconfig salvo: $KUBE_PATH"

    echo ""
    echo -e "${BOLD}Validando acesso local:${NC}"
    KUBECONFIG="$KUBE_PATH" kubectl get nodes 2>/dev/null \
        && ok "kubectl get nodes — OK" \
        || warn "kubectl get nodes falhou — verifique firewall (porta 6443 de $(hostname -I 2>/dev/null | awk '{print $1}'))"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  🎉 Kubernetes (kubeadm) bootstrapped em: $SSH_HOST${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════${NC}"
echo ""
if [[ -z "$JOIN_SERVER" ]]; then
    echo -e "${CYAN}Usar cluster:${NC}"
    echo -e "  export KUBECONFIG=${HOME}/.kube/${CLUSTER_NAME}.yaml"
    echo -e "  kubectl get nodes"
    echo ""
    echo -e "${CYAN}Adicionar worker node (via TUI → Bootstrap → opção 4):${NC}"
    echo -e "  ou: kubeadm token create --print-join-command   (no servidor)"
fi
echo ""
echo -e "${CYAN}Próximos passos no TUI → Cluster Bootstrap:${NC}"
echo -e "  5. Instalar nginx-Ingress (HTTP/S)"
echo -e "  6. Instalar Observabilidade (Coroot)"
echo -e "  9. Smoke Test"
echo ""
