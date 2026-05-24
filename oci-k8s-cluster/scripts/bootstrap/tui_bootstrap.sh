#!/usr/bin/env bash
# scripts/bootstrap/tui_bootstrap.sh
# TUI Module: Bootstrap a New K8s (k3s) Cluster on Any Machine
#
# Usage: source this file, then call bootstrap_cluster_menu
#
# Philosophy:
#   k3s first — lightweight (single binary, <512MB overhead), ARM64 + x86_64,
#   any cloud, zero licensing cost, high-security by default.
#
#   Steps guided by the menu (can be run individually, all idempotent):
#   1. Select target machine (SSH host)
#   2. Pre-flight: verify SSH + hardware
#   3. Bootstrap k3s server (single-node all-in-one)
#   4. Add worker node (join)
#   5. Install nginx-ingress
#   6. Install Coroot observability
#   7. Apply security hardening (journal limits + UFW)
#   8. Download kubeconfig locally
#   9. Smoke test
#
# Design notes:
#   • Session state is stored in _BS_* variables (cleared on return)
#   • All SSH commands go to _BS_HOST (not MASTER_NODE)
#   • Worker join uses the server's node-token fetched live
#   • kubeconfig saved to ~/.kube/<cluster-name>.yaml

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Session state ─────────────────────────────────────────────────────────────
_BS_HOST=""         # SSH target for this bootstrap session
_BS_NAME="k8s"      # Cluster/kubeconfig name (default matches kubeadm)
_BS_KUBECONFIG=""   # Local kubeconfig path (set after step 8)
_BS_DISTRO=""       # "kubeadm" (vanilla, ≥2vCPU/4GB) or "k3s" (leve, any machine)
_BS_DISTRO_CPU=0    # Detected vCPU count (set by pre-flight)
_BS_DISTRO_RAM=0    # Detected RAM MB (set by pre-flight)
_BS_DISTRO_ARCH=""  # Detected architecture (set by pre-flight)

_SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

# ── Helper: pick SSH host from ~/.ssh/config or type manually ─────────────────
_bs_select_host() {
    local known_hosts
    known_hosts=$(grep -E "^Host " ~/.ssh/config 2>/dev/null \
        | awk '{print $2}' | grep -v '\*' | sort) || known_hosts=""

    local host_choice=""
    if [[ -n "$known_hosts" ]]; then
        host_choice=$(printf '%s\n[digitar manualmente]' "$known_hosts" \
            | "$FZF_BIN" --height=40% --layout=reverse --border \
                --prompt="Host SSH alvo > " \
                --header="Hosts em ~/.ssh/config  (ESC = cancelar)") || true
    fi

    if [[ -z "$host_choice" ]] || [[ "$host_choice" == "[digitar manualmente]" ]]; then
        host_choice=$(whiptail --inputbox \
            "Digite o hostname/IP SSH da máquina alvo:\n(deve existir em ~/.ssh/config ou ser acessível por chave)" \
            10 65 "" --title "Host SSH" 3>&1 1>&2 2>&3) || return 1
    fi
    echo "$host_choice"
}

# ── Recommend distro based on hardware ───────────────────────────────────────
# Returns "kubeadm" for ≥ 2 vCPU AND ≥ 4 GB RAM — e.g. Hetzner, SSDNodes
# Returns "k3s" for constrained machines — e.g. OCI Ampere 1vCPU/6GB
# Architecture (ARM64/x86_64) does NOT affect the decision: both support both.
_bs_recommend_distro() {
    local cpu=$1 ram_mb=$2
    if [[ "$cpu" -ge 2 && "$ram_mb" -ge 4000 ]]; then
        echo "kubeadm"
    else
        echo "k3s"
    fi
}

# ── Interactive distro selection via fzf ─────────────────────────────────────
_bs_choose_distro() {
    local rec="$1" cpu="${2:-?}" ram="${3:-?}" arch="${4:-?}"
    local rec_tag="" k3s_tag=""
    [[ "$rec" == "kubeadm" ]] \
        && rec_tag=" ← RECOMENDADO (${cpu}vCPU / ${ram}MB)" \
        || k3s_tag=" ← RECOMENDADO (${cpu}vCPU / ${ram}MB)"

    local arch_note="($arch)"
    case "$arch" in
        aarch64|arm64) arch_note="(ARM64 — suportado por ambas)" ;;
        x86_64|amd64)  arch_note="(x86_64 — suportado por ambas)" ;;
    esac

    local menu
    menu=$(printf '%s\n' \
        "kubeadm — Kubernetes vanilla | pkgs.k8s.io | mín: 2vCPU + 4GB | etcd | ecossistema pleno${rec_tag}" \
        "k3s     — Kubernetes leve    | single binary | mín: 1vCPU + 512MB | SQLite | ARM64+x86${k3s_tag}")

    local chosen
    chosen=$(echo "$menu" | "$FZF_BIN" \
        --height=30% --layout=reverse --border \
        --prompt="Distribuição K8s > " \
        --header="Escolha a distribuição ${arch_note}:") || true

    if [[ -z "$chosen" ]]; then
        echo "$rec"   # ESC = usa a recomendação
        return
    fi
    [[ "$chosen" == k3s* ]] && echo "k3s" || echo "kubeadm"
}

# ── Pre-flight: SSH check + hardware report + distro recommendation ───────────
_bs_preflight() {
    local host="$1"
    echo -e "\n${CYAN}🔌 Verificando SSH em ${BOLD}$host${NC}${CYAN}...${NC}"

    if ! ssh $_SSH_OPTS "$host" "exit" 2>/dev/null; then
        echo -e "${RED}❌ SSH falhou para $host${NC}"
        echo -e "${YELLOW}  → Verifique ~/.ssh/config (alias correto?)"
        echo -e "  → Chave pública em authorized_keys do host?"
        echo -e "  → Teste manual: ssh $host${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ SSH OK${NC}\n"

    # Capture arch/cpu/ram for local recommendation logic
    local _hw_data
    _hw_data=$(ssh $_SSH_OPTS "$host" \
        "printf '%s %s %s' \"\$(uname -m)\" \"\$(nproc)\" \"\$(free -m | awk '/^Mem:/{print \$2}')\"" \
        2>/dev/null) || _hw_data=""
    local _pf_arch _pf_cpu _pf_ram
    read -r _pf_arch _pf_cpu _pf_ram <<< "$_hw_data" || true
    _BS_DISTRO_ARCH="${_pf_arch:-}"
    _BS_DISTRO_CPU="${_pf_cpu:-0}"
    _BS_DISTRO_RAM="${_pf_ram:-0}"

    echo -e "${CYAN}📊 Hardware detectado:${NC}"
    ssh $_SSH_OPTS "$host" '
        arch=$(uname -m)
        os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d "\"" || uname -s)
        cpu=$(nproc)
        ram_mb=$(free -m | awk "/^Mem:/{print \$2}")
        disk_gb=$(df -BG / | awk "NR==2{gsub(/G/,\"\",\$4); print \$4}")
        k3s_ver=$(k3s --version 2>/dev/null | head -1 || echo "não instalado")
        kube_ver=$(kubectl version --client --short 2>/dev/null | head -1 || echo "não instalado")
        printf "  %-14s %s\n" "Arch:"    "$arch"
        printf "  %-14s %s\n" "OS:"      "$os"
        printf "  %-14s %s vCPU(s)\n" "CPU:" "$cpu"
        printf "  %-14s %s MB\n" "RAM:" "$ram_mb"
        printf "  %-14s %s GB livres\n" "Disco (/):" "$disk_gb"
        printf "  %-14s %s\n" "kubectl:" "$kube_ver"
        printf "  %-14s %s\n" "k3s:" "$k3s_ver"
        echo ""
        [ "$disk_gb" -lt 5    ] && echo "  ❌ Disco insuficiente (mínimo 5GB para K8s)"
        [ "$disk_gb" -ge 5    ] && [ "$disk_gb" -lt 20 ] && echo "  ⚠️  Disco apertado (recomendado 20GB+)"
        [ "$disk_gb" -ge 20   ] && echo "  ✅ Disco adequado"
    '

    # Show recommendation and trigger distro selection
    if [[ -n "$_pf_cpu" && "$_pf_cpu" != "0" ]]; then
        local _rec
        _rec=$(_bs_recommend_distro "$_pf_cpu" "$_pf_ram")
        echo -e "\n${CYAN}Análise de recursos (${BOLD}${_pf_cpu}vCPU / ${_pf_ram}MB / ${_pf_arch}${NC}${CYAN}):${NC}"
        if [[ "$_rec" == "kubeadm" ]]; then
            echo -e "  ${GREEN}✅ Recursos suficientes → ${BOLD}kubeadm${NC}${GREEN} (Kubernetes vanilla) recomendado${NC}"
            echo -e "     Ex: Hetzner CAX21 (4vCPU/8GB), SSDNodes (12vCPU/60GB) → kubeadm"
        else
            echo -e "  ${YELLOW}⚡ Recursos limitados → ${BOLD}k3s${NC}${YELLOW} (Kubernetes leve) recomendado${NC}"
            echo -e "     Ex: OCI Ampere free tier (1vCPU/6GB) → k3s"
        fi
        echo ""

        if [[ -z "$_BS_DISTRO" ]]; then
            local _chosen
            _chosen=$(_bs_choose_distro "$_rec" "$_pf_cpu" "$_pf_ram" "$_pf_arch")
            _BS_DISTRO="$_chosen"
        else
            echo -e "  Distribuição atual: ${BOLD}${_BS_DISTRO}${NC}"
            local _change
            read -rp "  Alterar distribuição? (s/N): " _change
            if [[ "$_change" =~ ^[sS]$ ]]; then
                local _new
                _new=$(_bs_choose_distro "$_rec" "$_pf_cpu" "$_pf_ram" "$_pf_arch")
                _BS_DISTRO="$_new"
            fi
        fi
        echo -e "\n${GREEN}✅ Distribuição selecionada: ${BOLD}${_BS_DISTRO}${NC}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────────────────────────────────────────
bootstrap_cluster_menu() {
    while true; do
        local host_info="${_BS_HOST:-[não selecionado]}"
        local kube_info="${_BS_KUBECONFIG:-[aguardando bootstrap]}"
        local distro_label="${_BS_DISTRO:-[fazer pre-flight (2)]}"

        # Item 3 title shows the currently selected distribution
        local _item3_label="Bootstrap ${_BS_DISTRO:-kubeadm/k3s} — Nó Único (all-in-one) 🚀"

        local actions
        actions="$(cat <<MENU
1. Selecionar Máquina Alvo (SSH) 🖥️
2. Pre-flight: SSH, Hardware & Distribuição K8s 🔌
3. ${_item3_label}
4. Adicionar Worker Node (Join) 🤝
5. Instalar nginx-Ingress (HTTP/HTTPS) 🌐
6. Instalar Observabilidade — Coroot 🔭
7. Hardening de Segurança (journal + UFW) 🛡️
8. Baixar Kubeconfig Localmente 📥
9. Smoke Test (Verificar Cluster) 🔍
0. Voltar ao Menu Principal
MENU
)"

        local selected
        selected=$(echo "$actions" | "$FZF_BIN" \
            --height=65% \
            --layout=reverse \
            --border \
            --prompt="Cluster Bootstrap > " \
            --header="$(printf 'Alvo: %-22s | Distro: %-9s | Kubeconfig: %s' "$host_info" "$distro_label" "$kube_info")") || true

        [[ -z "$selected" ]] && return

        case "${selected%%.*}" in
            # ── 1. Select target host ─────────────────────────────────────────
            1)
                local chosen
                chosen=$(_bs_select_host 2>&1) || { read -rp "Press Enter..."; continue; }
                [[ -z "$chosen" ]] && { read -rp "Press Enter..."; continue; }
                _BS_HOST="$chosen"
                # Suggest cluster name from host alias
                local suggested
                suggested=$(echo "$chosen" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/-\{2,\}/-/g' | tr '[:upper:]' '[:lower:]' | sed 's/-$//')
                local chosen_name
                chosen_name=$(whiptail --inputbox \
                    "Nome do cluster (usado no kubeconfig context):" \
                    8 55 "$suggested" --title "Nome do Cluster" \
                    3>&1 1>&2 2>&3) || chosen_name="$suggested"
                [[ -n "$chosen_name" ]] && _BS_NAME="$chosen_name"
                echo -e "\n${GREEN}✅ Selecionado: ${BOLD}$_BS_HOST${NC}${GREEN} | Cluster: ${BOLD}$_BS_NAME${NC}"
                read -rp "Press Enter..."
                ;;

            # ── 2. Pre-flight ─────────────────────────────────────────────────
            2)
                if [[ -z "$_BS_HOST" ]]; then
                    echo -e "\n${YELLOW}⚠️  Selecione a máquina alvo primeiro (opção 1)${NC}"
                else
                    _bs_preflight "$_BS_HOST" || true
                fi
                read -rp "Press Enter..."
                ;;

            # ── 3. Bootstrap cluster (kubeadm or k3s) ────────────────────────
            3)
                if [[ -z "$_BS_HOST" ]]; then
                    echo -e "\n${YELLOW}⚠️  Selecione a máquina alvo primeiro (opção 1)${NC}"
                    read -rp "Press Enter..."; continue
                fi
                if [[ -z "$_BS_DISTRO" ]]; then
                    echo -e "\n${YELLOW}⚠️  Execute o pre-flight primeiro (opção 2) para detectar hardware e selecionar distribuição${NC}"
                    read -rp "Press Enter..."; continue
                fi
                local _distro="${_BS_DISTRO}"
                local _distro_desc
                [[ "$_distro" == "kubeadm" ]] \
                    && _distro_desc="Kubernetes vanilla (kubeadm + Flannel CNI)" \
                    || _distro_desc="Kubernetes leve (k3s, single binary)"
                echo -e "\n${YELLOW}╔══════════════════════════════════════════════╗"
                echo -e "║  Bootstrap em:   ${BOLD}$_BS_HOST${YELLOW}$(printf '%*s' $((44 - ${#_BS_HOST} - 2)) '')║"
                echo -e "║  Distribuição:   ${BOLD}${_distro}${YELLOW}$(printf '%*s' $((44 - ${#_distro} - 2)) '')║"
                echo -e "║  Cluster name:   ${BOLD}$_BS_NAME${YELLOW}$(printf '%*s' $((44 - ${#_BS_NAME} - 2)) '')║"
                echo -e "╚══════════════════════════════════════════════╝${NC}"
                echo ""
                echo -e "Irá instalar: ${CYAN}${_distro_desc}${NC}"
                echo -e "  • Hardening: journal limits 200M + UFW firewall"
                echo -e "  • Kubeconfig: ~/.kube/${_BS_NAME}.yaml"
                echo ""
                read -rp "Confirmar? (s/N): " confirm
                if [[ "$confirm" =~ ^[sS]$ ]]; then
                    if [[ "$_distro" == "k3s" ]]; then
                        bash "$BOOTSTRAP_DIR/install_k3s_server.sh" "$_BS_HOST" \
                            --name "$_BS_NAME"
                    else
                        bash "$BOOTSTRAP_DIR/install_k8s_kubeadm.sh" "$_BS_HOST" \
                            --name "$_BS_NAME"
                    fi
                    _BS_KUBECONFIG="${HOME}/.kube/${_BS_NAME}.yaml"
                else
                    echo "Cancelado."
                fi
                read -rp "Press Enter..."
                ;;

            # ── 4. Add worker node ────────────────────────────────────────────
            4)
                if [[ -z "$_BS_HOST" ]]; then
                    echo -e "\n${YELLOW}⚠️  Bootstrap o servidor primeiro (opção 3)${NC}"
                    read -rp "Press Enter..."; continue
                fi
                echo -e "\n${CYAN}Selecione a máquina worker (host SSH diferente do servidor):${NC}"
                local worker_host
                worker_host=$(_bs_select_host 2>&1) || { read -rp "Press Enter..."; continue; }
                [[ -z "$worker_host" ]] && { read -rp "Press Enter..."; continue; }
                if [[ "$worker_host" == "$_BS_HOST" ]]; then
                    echo -e "${RED}❌ Worker deve ser um host diferente do servidor${NC}"
                    read -rp "Press Enter..."; continue
                fi
                echo -e "\n${YELLOW}Adicionar ${BOLD}$worker_host${NC}${YELLOW} como worker (${_BS_DISTRO:-kubeadm}) no cluster ${BOLD}$_BS_NAME${NC}${YELLOW}?${NC}"
                read -rp "Confirmar? (s/N): " confirm
                if [[ "$confirm" =~ ^[sS]$ ]]; then
                    if [[ "${_BS_DISTRO:-kubeadm}" == "k3s" ]]; then
                        bash "$BOOTSTRAP_DIR/install_k3s_server.sh" "$worker_host" \
                            --name "$_BS_NAME" \
                            --join-server "$_BS_HOST"
                    else
                        bash "$BOOTSTRAP_DIR/install_k8s_kubeadm.sh" "$worker_host" \
                            --name "$_BS_NAME" \
                            --join-server "$_BS_HOST"
                    fi
                else
                    echo "Cancelado."
                fi
                read -rp "Press Enter..."
                ;;

            # ── 5. Install nginx-ingress ──────────────────────────────────────
            5)
                if [[ -z "$_BS_HOST" ]]; then
                    echo -e "\n${YELLOW}⚠️  Bootstrap o servidor primeiro (opção 3)${NC}"
                    read -rp "Press Enter..."; continue
                fi
                echo -e "\n${CYAN}🌐 Instalando nginx-ingress em $_BS_HOST...${NC}"
                echo -e "${YELLOW}(baremetal/NodePort — adequado para qualquer cloud)${NC}\n"
                local _nginx_distro="${_BS_DISTRO:-kubeadm}"
                ssh $_SSH_OPTS "$_BS_HOST" "KUBE_DISTRO='$_nginx_distro' bash -s" << 'NGINX_EOF'
                    set -e
                    [[ "$KUBE_DISTRO" == "k3s" ]] && KUBECTL="sudo kubectl" || KUBECTL="kubectl"
                    echo "Aplicando manifesto nginx-ingress (baremetal)..."
                    $KUBECTL apply -f \
                        https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.0/deploy/static/provider/baremetal/deploy.yaml
                    echo "Aguardando ingress-nginx controller (timeout 2min)..."
                    $KUBECTL wait --namespace ingress-nginx \
                        --for=condition=ready pod \
                        --selector=app.kubernetes.io/component=controller \
                        --timeout=120s 2>/dev/null \
                        && echo "✅ nginx-ingress pronto" \
                        || echo "⏳ Ainda inicializando — verifique: kubectl get pods -n ingress-nginx"
                    echo ""
                    $KUBECTL get svc -n ingress-nginx
NGINX_EOF
                read -rp "Press Enter..."
                ;;

            # ── 6. Install Coroot observability ──────────────────────────────
            6)
                if [[ -z "$_BS_HOST" ]]; then
                    echo -e "\n${YELLOW}⚠️  Bootstrap o servidor primeiro (opção 3)${NC}"
                    read -rp "Press Enter..."; continue
                fi
                echo -e "\n${CYAN}🔭 Instalando Coroot (community) em $_BS_HOST...${NC}"
                echo -e "${YELLOW}Inclui: ClickHouse + Prometheus + node-agent + UI${NC}"
                echo -e "${YELLOW}Tempo estimado: 3-5 min (download de imagens)${NC}\n"
                # Pass distro info so helm uses the right kubeconfig on the remote
                local _coroot_distro="${_BS_DISTRO:-kubeadm}"
                ssh $_SSH_OPTS "$_BS_HOST" "KUBE_DISTRO='$_coroot_distro' bash -s" << 'COROOT_EOF'
                    set -e
                    # Install helm if not present
                    if ! command -v helm &>/dev/null; then
                        echo "Instalando helm..."
                        curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                    fi
                    helm repo add coroot https://coroot.github.io/helm-charts 2>/dev/null || true
                    helm repo update 2>/dev/null

                    # Select kubeconfig path based on distribution
                    if [[ "$KUBE_DISTRO" == "k3s" ]]; then
                        KUBE_ARG="--kubeconfig /etc/rancher/k3s/k3s.yaml"
                        KUBECTL="sudo kubectl"
                    else
                        KUBE_ARG=""   # helm uses ~/.kube/config (set by kubeadm)
                        KUBECTL="kubectl"
                    fi

                    $KUBECTL create namespace coroot --dry-run=client -o yaml | $KUBECTL apply -f -
                    # Single-shard ClickHouse (fits in 1-2 GB RAM)
                    helm upgrade --install coroot coroot/coroot \
                        --namespace coroot \
                        --set clickhouse.shards=1 \
                        --set clickhouse.replicas=1 \
                        $KUBE_ARG \
                        --timeout 8m \
                        --wait
                    echo ""
                    echo "✅ Coroot instalado"
                    echo ""
                    echo "Para acessar:"
                    echo "  kubectl port-forward -n coroot svc/coroot 8080:8080"
                    echo "  Abrir: http://localhost:8080"
                    echo ""
                    $KUBECTL get pods -n coroot
COROOT_EOF
                read -rp "Press Enter..."
                ;;

            # ── 7. Security hardening ─────────────────────────────────────────
            7)
                if [[ -z "$_BS_HOST" ]]; then
                    echo -e "\n${YELLOW}⚠️  Selecione a máquina alvo primeiro (opção 1)${NC}"
                    read -rp "Press Enter..."; continue
                fi
                echo -e "\n${CYAN}🛡️  Aplicando hardening em $_BS_HOST...${NC}\n"
                # Reuse install_k3s_server.sh's hardening step (--no-hardening skips k3s install)
                # Actually, just call the hardening inline since we don't want to re-install k3s
                ssh $_SSH_OPTS "$_BS_HOST" '
                    # ── Journal limits (T-293 lesson: 200M cap prevents iowait spikes)
                    _ao() {
                        local key=$1 val=$2 file=/etc/systemd/journald.conf
                        if sudo grep -qE "^#?${key}=" "$file" 2>/dev/null; then
                            sudo sed -i "s|^#\?\(${key}\)=.*|\1=${val}|" "$file"
                        else
                            echo "${key}=${val}" | sudo tee -a "$file" >/dev/null
                        fi
                    }
                    _ao SystemMaxUse      200M
                    _ao SystemKeepFree    500M
                    _ao SystemMaxFileSize  50M
                    _ao MaxRetentionSec   7day
                    _ao RuntimeMaxUse      50M
                    sudo systemctl restart systemd-journald
                    sudo journalctl --vacuum-size=200M 2>&1 | grep -E "Freed|freed|No archive" || true
                    echo "✅ Journal: 200M cap + 7d retention aplicados"

                    # ── UFW firewall
                    if command -v ufw >/dev/null 2>&1; then
                        sudo ufw --force reset         >/dev/null 2>&1
                        sudo ufw default deny incoming  >/dev/null 2>&1
                        sudo ufw default allow outgoing >/dev/null 2>&1
                        sudo ufw allow 22/tcp    comment SSH     >/dev/null 2>&1
                        sudo ufw allow 6443/tcp  comment k8s-api >/dev/null 2>&1
                        sudo ufw allow 443/tcp   comment HTTPS   >/dev/null 2>&1
                        sudo ufw allow 80/tcp    comment HTTP    >/dev/null 2>&1
                        sudo ufw allow 8472/udp  comment flannel >/dev/null 2>&1
                        sudo ufw allow 10250/tcp comment kubelet  >/dev/null 2>&1
                        sudo ufw --force enable  >/dev/null 2>&1
                        echo "✅ UFW: deny-all + allow SSH/k8s/HTTP(S)/Flannel"
                        sudo ufw status numbered
                    else
                        echo "⚠️  ufw não disponível — instale: apt install ufw"
                    fi

                    # ── Docker log limits (if present)
                    if command -v docker >/dev/null 2>&1; then
                        sudo mkdir -p /etc/docker
                        [ -f /etc/docker/daemon.json ] || echo "{}" | sudo tee /etc/docker/daemon.json >/dev/null
                        sudo python3 - <<'"'"'PY'"'"'
import json
path = "/etc/docker/daemon.json"
with open(path) as f: d = json.load(f)
d.setdefault("log-driver", "json-file")
d.setdefault("log-opts", {})["max-size"] = "100m"
d["log-opts"]["max-file"] = "3"
with open(path, "w") as f: json.dump(d, f, indent=2)
PY
                        echo "✅ Docker log limits: 100m max-size, 3 files"
                    fi
                ' || true
                read -rp "Press Enter..."
                ;;

            # ── 8. Download kubeconfig ────────────────────────────────────────
            8)
                if [[ -z "$_BS_HOST" ]]; then
                    echo -e "\n${YELLOW}⚠️  Bootstrap o servidor primeiro (opção 3)${NC}"
                    read -rp "Press Enter..."; continue
                fi
                echo -e "\n${CYAN}📥 Baixando kubeconfig de $_BS_HOST...${NC}"
                local kube_dir="${HOME}/.kube"
                mkdir -p "$kube_dir"
                local kube_path="${kube_dir}/${_BS_NAME}.yaml"
                local remote_ip
                remote_ip=$(ssh $_SSH_OPTS "$_BS_HOST" "hostname -I | awk '{print \$1}'" 2>/dev/null) \
                    || remote_ip="$_BS_HOST"

                # k3s: kubeconfig is at /etc/rancher/k3s/k3s.yaml with 127.0.0.1 → needs IP replacement
                # kubeadm: kubeconfig at ~/.kube/config already has real IP (no substitution needed)
                local _kube_remote_path _do_ip_replace
                if [[ "${_BS_DISTRO:-kubeadm}" == "k3s" ]]; then
                    _kube_remote_path="/etc/rancher/k3s/k3s.yaml"
                    _do_ip_replace=true
                else
                    _kube_remote_path="\$HOME/.kube/config"
                    _do_ip_replace=false
                fi

                local _kube_raw
                _kube_raw=$(ssh $_SSH_OPTS "$_BS_HOST" \
                    "cat $_kube_remote_path 2>/dev/null || sudo cat $_kube_remote_path 2>/dev/null") || _kube_raw=""

                if [[ -n "$_kube_raw" ]]; then
                    if [[ "$_do_ip_replace" == "true" ]]; then
                        echo "$_kube_raw" \
                            | sed "s/127\.0\.0\.1/${remote_ip}/g" \
                            | sed "s/: default$/: ${_BS_NAME}/g" \
                            | sed "s/: kubernetes$/: ${_BS_NAME}/g" \
                            > "$kube_path"
                    else
                        echo "$_kube_raw" \
                            | sed "s/: kubernetes$/: ${_BS_NAME}/g" \
                            | sed "s/: kubernetes-admin$/: ${_BS_NAME}-admin/g" \
                            > "$kube_path"
                    fi
                    chmod 600 "$kube_path"
                    _BS_KUBECONFIG="$kube_path"
                    echo -e "${GREEN}✅ Kubeconfig salvo: $kube_path${NC}"
                    echo ""
                    echo -e "${CYAN}Usar:${NC}"
                    echo -e "  export KUBECONFIG=$kube_path"
                    echo -e "  kubectl get nodes"
                    echo ""
                    KUBECONFIG="$kube_path" kubectl get nodes 2>/dev/null \
                        && echo -e "${GREEN}✅ kubectl get nodes — OK${NC}" \
                        || echo -e "${YELLOW}⚠️  Verifique se porta 6443 está acessível de $(hostname -I | awk '{print $1}' 2>/dev/null)${NC}"
                else
                    echo -e "${RED}❌ Falha ao baixar kubeconfig de $_kube_remote_path${NC}"
                    echo "  Tente manualmente: ssh $_BS_HOST 'cat ~/.kube/config'"
                fi
                read -rp "Press Enter..."
                ;;

            # ── 9. Smoke test ─────────────────────────────────────────────────
            9)
                if [[ -z "$_BS_HOST" ]]; then
                    echo -e "\n${YELLOW}⚠️  Bootstrap o servidor primeiro (opção 3)${NC}"
                    read -rp "Press Enter..."; continue
                fi
                echo -e "\n${CYAN}🔍 Smoke Test — cluster em $_BS_HOST (${_BS_DISTRO:-kubeadm})${NC}\n"
                # k3s uses sudo kubectl; kubeadm sets up kubectl for the user
                local _smoke_distro="${_BS_DISTRO:-kubeadm}"
                ssh $_SSH_OPTS "$_BS_HOST" "KUBE_DISTRO='$_smoke_distro' bash -s" << 'SMOKE_EOF'
                    set -e
                    if [[ "$KUBE_DISTRO" == "k3s" ]]; then
                        kctl() { sudo kubectl "$@"; }
                        version_info() { k3s --version 2>/dev/null || echo "k3s: n/a"; }
                    else
                        kctl() { kubectl "$@"; }
                        version_info() { kubectl version --short 2>/dev/null || kubectl version 2>/dev/null | head -3; }
                    fi

                    echo "=== Nodes ==="
                    kctl get nodes -o wide
                    echo ""
                    echo "=== System Pods ==="
                    kctl get pods -n kube-system --no-headers \
                        | awk "{printf \"  %-40s %s\n\", \$1, \$4}"
                    echo ""
                    echo "=== Storage Classes ==="
                    kctl get storageclass 2>/dev/null || echo "  (nenhuma)"
                    echo ""
                    echo "=== Namespaces ==="
                    kctl get namespaces
                    echo ""
                    echo "=== Versão K8s ==="
                    version_info
                    echo ""
                    # Quick deploy test
                    echo "=== Deploy test (nginx:alpine) ==="
                    kctl run smoke-test --image=nginx:alpine --restart=Never \
                        --overrides='{"spec":{"terminationGracePeriodSeconds":0}}' \
                        2>/dev/null || echo "(pod já existe)"
                    sleep 6
                    kctl get pod smoke-test 2>/dev/null | tail -1
                    kctl delete pod smoke-test --grace-period=0 --ignore-not-found 2>/dev/null || true
                    echo "✅ Smoke test concluído"
SMOKE_EOF
                read -rp "Press Enter..."
                ;;

            # ── 0. Back ───────────────────────────────────────────────────────
            0) return ;;
        esac
    done
}
