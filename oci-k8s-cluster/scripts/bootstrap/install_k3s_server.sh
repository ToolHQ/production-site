#!/usr/bin/env bash
# scripts/bootstrap/install_k3s_server.sh
# Bootstrap k3s on a remote SSH host (control plane or worker node)
#
# Philosophy: k3s first — single binary, ARM64/x86, <512 MB overhead,
# any cloud, low-cost, high-security. Run via TUI (tui_bootstrap.sh)
# or standalone.
#
# Usage (server):
#   ./install_k3s_server.sh <ssh-host> [options]
#
# Usage (worker join):
#   ./install_k3s_server.sh <ssh-host> --join-server <server-host>
#
# Options:
#   --name <cluster-name>    Used in kubeconfig context name (default: k3s)
#   --version <tag>          k3s version, e.g. v1.30.1+k3s1 (default: latest stable)
#   --join-server <host>     SSH host of the server to join as worker
#   --no-hardening           Skip journal limits + UFW hardening
#   --skip-kubeconfig        Don't download kubeconfig locally
#
# What it installs:
#   k3s server  → API server, etcd, scheduler, controller-manager, kubelet, proxy
#   Built-in:   → Flannel CNI, CoreDNS, local-path-provisioner, metrics-server (disabled)
#   Disabled:   → Traefik (use ingress-nginx separately — smaller footprint)
#   Security:   → Journal limits 200M + UFW firewall
#
# After install, kubeconfig is saved to: ~/.kube/<cluster-name>.yaml

set -euo pipefail

SSH_HOST="${1:?Usage: $0 <ssh-host> [--name NAME] [--version TAG] [--join-server HOST]}"
shift

CLUSTER_NAME="k3s"
K3S_VERSION=""       # empty = latest stable from channel=stable
JOIN_SERVER=""       # if set → install as agent (worker)
DO_HARDENING=true
SKIP_KUBECONFIG=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)           CLUSTER_NAME="$2";  shift 2 ;;
        --version)        K3S_VERSION="$2";   shift 2 ;;
        --join-server)    JOIN_SERVER="$2";   shift 2 ;;
        --no-hardening)   DO_HARDENING=false; shift   ;;
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
# STEP 1: Pre-flight checks
# ─────────────────────────────────────────────────────────────────────────────
step "1/5" "Pre-flight: conectividade SSH e hardware em $SSH_HOST"

ssh $SSH_OPTS "$SSH_HOST" "exit" 2>/dev/null || fail "SSH falhou para $SSH_HOST. Verifique ~/.ssh/config e authorized_keys."
ok "SSH OK"

read -r REMOTE_ARCH REMOTE_OS REMOTE_RAM REMOTE_DISK REMOTE_CPU < <(
    ssh $SSH_OPTS "$SSH_HOST" \
        "echo \"\$(uname -m) \$(grep -oP '(?<=^ID=\"?).*(?=\"?)' /etc/os-release 2>/dev/null || uname -s) \$(free -m | awk '/^Mem:/{print \$2}') \$(df -BG / | awk 'NR==2{gsub(/G/,\"\",\$4); print \$4}') \$(nproc)\""
)

echo -e "  Arch: ${BOLD}$REMOTE_ARCH${NC}  OS: ${BOLD}$REMOTE_OS${NC}  CPU: ${BOLD}${REMOTE_CPU}vCPU${NC}  RAM: ${BOLD}${REMOTE_RAM}MB${NC}  Disco livre: ${BOLD}${REMOTE_DISK}GB${NC}"

[[ "$REMOTE_RAM"  -lt 400 ]] && fail "RAM insuficiente: ${REMOTE_RAM}MB (mínimo 400MB para k3s)"
[[ "$REMOTE_DISK" -lt 5   ]] && fail "Disco insuficiente: ${REMOTE_DISK}GB (mínimo 5GB livres)"

# Check if k3s already installed
if ssh $SSH_OPTS "$SSH_HOST" "command -v k3s &>/dev/null" 2>/dev/null; then
    warn "k3s já instalado neste host. A instalação atualizará a versão se --version foi fornecido."
fi
ok "Hardware verificado"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2: Install k3s (server or agent)
# ─────────────────────────────────────────────────────────────────────────────
if [[ -n "$JOIN_SERVER" ]]; then
    step "2/5" "Instalando k3s agent (worker) em $SSH_HOST → joining $JOIN_SERVER"

    # Get server IP and token from the server
    echo -e "  Obtendo IP e token do servidor $JOIN_SERVER..."
    SERVER_IP=$(ssh $SSH_OPTS "$JOIN_SERVER" "hostname -I | awk '{print \$1}'" 2>/dev/null) \
        || fail "Não foi possível obter IP do servidor $JOIN_SERVER"
    NODE_TOKEN=$(ssh $SSH_OPTS "$JOIN_SERVER" "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null) \
        || fail "Não foi possível obter node-token do servidor $JOIN_SERVER (k3s instalado?)"

    VERSION_ENV=""
    [[ -n "$K3S_VERSION" ]] && VERSION_ENV="INSTALL_K3S_VERSION='${K3S_VERSION}'"

    ssh -t $SSH_OPTS "$SSH_HOST" "
        set -e
        echo '📦 Instalando k3s agent...'
        curl -sfL https://get.k3s.io | \
            K3S_URL='https://${SERVER_IP}:6443' \
            K3S_TOKEN='${NODE_TOKEN}' \
            ${VERSION_ENV} \
            sh -
        echo '✅ k3s agent instalado e conectado ao cluster'
    "
    ok "Worker node instalado e conectado"
    SKIP_KUBECONFIG=true  # kubeconfig is on the server

else
    step "2/5" "Instalando k3s server (control plane + all-in-one) em $SSH_HOST"

    VERSION_ENV=""
    [[ -n "$K3S_VERSION" ]] && VERSION_ENV="INSTALL_K3S_VERSION='${K3S_VERSION}'"

    # k3s server flags (security & resource conscious):
    #   --disable traefik       → smaller footprint, use ingress-nginx if needed
    #   --disable metrics-server → install separately if needed (saves RAM)
    #   --secrets-encryption     → encrypt secrets at rest (etcd)
    #   --write-kubeconfig-mode 644 → allow non-root read of /etc/rancher/k3s/k3s.yaml
    ssh -t $SSH_OPTS "$SSH_HOST" "
        set -e
        echo '📦 Instalando k3s server...'
        curl -sfL https://get.k3s.io | \
            INSTALL_K3S_EXEC='server
                --disable traefik
                --disable metrics-server
                --secrets-encryption
                --write-kubeconfig-mode 644' \
            ${VERSION_ENV} \
            sh -
        echo '✅ k3s server instalado'
    "
    ok "k3s server instalado"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3: Wait for cluster readiness
# ─────────────────────────────────────────────────────────────────────────────
step "3/5" "Aguardando cluster ficar Ready (timeout: 2min)"

ssh $SSH_OPTS "$SSH_HOST" "
    echo -n 'Aguardando nó Ready'
    timeout 120 bash -c '
        until sudo kubectl get nodes 2>/dev/null | grep -q \" Ready \"; do
            sleep 3; echo -n .
        done
    ' && echo '' || { echo ''; echo 'Timeout — verificando status:'; sudo kubectl get nodes 2>/dev/null; exit 1; }
    echo '--- Nodes ---'
    sudo kubectl get nodes -o wide
    echo ''
    echo '--- System Pods ---'
    sudo kubectl get pods -n kube-system --no-headers | head -20
"
ok "Cluster Ready"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4: Security hardening
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$DO_HARDENING" == "true" ]]; then
    step "4/5" "Aplicando hardening de segurança"

    ssh $SSH_OPTS "$SSH_HOST" "
        # ── Journal limits (previne disco cheio → iowait alto → CPU falso 100%)
        # Lição do T-293: coroot-node-agent lê TODOS os journals acumulados ao reiniciar.
        # Com 200M cap + 7d expiry, journals ficam pequenos e leitura é rápida.
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

        # ── UFW firewall (deny all in, allow k8s ports)
        if command -v ufw >/dev/null 2>&1; then
            sudo ufw --force reset                  >/dev/null 2>&1
            sudo ufw default deny incoming          >/dev/null 2>&1
            sudo ufw default allow outgoing         >/dev/null 2>&1
            sudo ufw allow 22/tcp    comment SSH    >/dev/null 2>&1
            sudo ufw allow 6443/tcp  comment k8s-api >/dev/null 2>&1
            sudo ufw allow 443/tcp   comment HTTPS  >/dev/null 2>&1
            sudo ufw allow 80/tcp    comment HTTP   >/dev/null 2>&1
            sudo ufw allow 8472/udp  comment flannel-vxlan >/dev/null 2>&1
            sudo ufw allow 10250/tcp comment kubelet >/dev/null 2>&1
            sudo ufw --force enable                 >/dev/null 2>&1
            echo '✅ UFW: deny-all-in + allow SSH/k8s/HTTP(S)/Flannel'
        else
            echo '⚠️  ufw não encontrado — instale com: apt install ufw'
        fi
    "
    ok "Hardening aplicado"
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5: Pull kubeconfig locally
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$SKIP_KUBECONFIG" == "false" ]]; then
    step "5/5" "Baixando kubeconfig para ~/.kube/${CLUSTER_NAME}.yaml"

    KUBE_DIR="${HOME}/.kube"
    mkdir -p "$KUBE_DIR"
    KUBE_PATH="${KUBE_DIR}/${CLUSTER_NAME}.yaml"

    # Get remote IP (k3s kubeconfig has 127.0.0.1 — replace with real IP)
    REMOTE_IP=$(ssh $SSH_OPTS "$SSH_HOST" "hostname -I | awk '{print \$1}'" 2>/dev/null) \
        || REMOTE_IP="$SSH_HOST"

    ssh $SSH_OPTS "$SSH_HOST" "sudo cat /etc/rancher/k3s/k3s.yaml" \
        | sed "s/127\.0\.0\.1/${REMOTE_IP}/g" \
        | sed "s/: default$/: ${CLUSTER_NAME}/g" \
        > "$KUBE_PATH"
    chmod 600 "$KUBE_PATH"
    ok "Kubeconfig salvo: $KUBE_PATH"

    echo ""
    echo -e "${BOLD}Validando acesso local:${NC}"
    KUBECONFIG="$KUBE_PATH" kubectl get nodes 2>/dev/null \
        && ok "kubectl get nodes — OK" \
        || warn "kubectl get nodes falhou — verifique firewall (porta 6443 acessível de $(hostname -I | awk '{print $1}'))"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  🎉 Cluster k3s bootstrapped em: $SSH_HOST${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
if [[ -z "$JOIN_SERVER" ]]; then
    REMOTE_IP_FINAL=$(ssh $SSH_OPTS "$SSH_HOST" "hostname -I | awk '{print \$1}'" 2>/dev/null) || REMOTE_IP_FINAL="$SSH_HOST"
    NODE_TOKEN_FINAL=$(ssh $SSH_OPTS "$SSH_HOST" "sudo cat /var/lib/rancher/k3s/server/node-token" 2>/dev/null) || NODE_TOKEN_FINAL="(ver /var/lib/rancher/k3s/server/node-token no host)"

    echo -e "${CYAN}Usar cluster:${NC}"
    echo -e "  export KUBECONFIG=${HOME}/.kube/${CLUSTER_NAME}.yaml"
    echo -e "  kubectl get nodes"
    echo ""
    echo -e "${CYAN}Adicionar worker node:${NC}"
    echo -e "  K3S_URL=https://${REMOTE_IP_FINAL}:6443"
    echo -e "  K3S_TOKEN=${NODE_TOKEN_FINAL}"
    echo -e "  (use a opção 'Adicionar Worker Node' no TUI → Cluster Bootstrap)"
fi
echo ""
echo -e "${CYAN}Próximos passos no TUI → Cluster Bootstrap:${NC}"
echo -e "  5. Instalar nginx-Ingress (ingresso HTTP/S)"
echo -e "  6. Instalar Observabilidade (Coroot)"
echo -e "  9. Smoke Test"
echo ""
