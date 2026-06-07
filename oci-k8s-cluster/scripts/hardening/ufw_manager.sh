#!/usr/bin/env bash
# oci-k8s-cluster/scripts/hardening/ufw_manager.sh
# Gerenciador de firewall UFW para máquinas remotas (ssdnodes-monstro e afins).
#
# Uso:
#   ufw_manager.sh [--host HOST] [--status|--apply|--disable]
#   ufw_manager.sh                          # modo interativo (fzf)
#
# Integração TUI: chamado pelo show_hardening_menu() em k8s_ops_menu.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
GITHUB_WEBHOOK_IPS_FILE="${GITHUB_WEBHOOK_IPS_FILE:-$REPO_ROOT/components/ssdnodes/github-webhook-ip-ranges.txt}"
FZF_BIN="${FZF_BIN:-/tmp/k8s_ops_fzf}"
[[ ! -x "$FZF_BIN" ]] && FZF_BIN="$(command -v fzf 2>/dev/null || echo fzf)"

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURAÇÃO DE HOSTS GERENCIADOS
# Adicione/remova hosts aqui. Cada entrada é um alias SSH (de ~/.ssh/config).
# ─────────────────────────────────────────────────────────────────────────────
declare -A MANAGED_HOSTS=(
    ["ssdnodes-monstro"]="104.225.218.78 | x86_64 | 12vCPU/60GB | Servidor dedicado SSDNodes"
)

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURAÇÃO DE IPs PERMITIDOS
#
# ADMIN_IPS: Acesso completo (SSH :22 + ingress :80/:443 + kube-api :6443)
# INGRESS_IPS: Apenas ingress (:80 e :443) — CI builders, cluster OCI
#
# Formato de cada item: "IP  # comentário"
# ─────────────────────────────────────────────────────────────────────────────

ADMIN_IPS=(
    "189.62.149.233  # Reinaldo — estação de trabalho"
)

INGRESS_IPS=(
    "37.27.85.100    # Hetzner CAX21 Helsinki — CI builder (GitHub Actions)"
    "150.136.34.254  # OCI k8s-master"
    "150.136.67.52   # OCI k8s-node-1"
    "150.136.70.212  # OCI k8s-node-2"
    "150.136.88.87   # OCI k8s-node-3"
)

# ─────────────────────────────────────────────────────────────────────────────
# Flags
# ─────────────────────────────────────────────────────────────────────────────
TARGET_HOST="ssdnodes-monstro"
ACTION=""

_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)     TARGET_HOST="$2"; shift 2 ;;
            --status)   ACTION="status"; shift ;;
            --apply)    ACTION="apply"; shift ;;
            --disable)  ACTION="disable"; shift ;;
            --dry-run)  ACTION="dry-run"; shift ;;
            -h|--help)
                echo "Uso: $0 [--host HOST] [--status|--apply|--disable|--dry-run]"
                exit 0
                ;;
            *) echo "Opção desconhecida: $1"; exit 1 ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
_SSH="ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no"

_ok()   { echo -e "\033[0;32m✔\033[0m  $*"; }
_warn() { echo -e "\033[1;33m⚠\033[0m  $*"; }
_err()  { echo -e "\033[0;31m✘\033[0m  $*" >&2; }
_info() { echo -e "\033[0;36mℹ\033[0m  $*"; }
_head() { echo -e "\n\033[1;34m══ $* \033[0m"; }

# Extrai só o IP de uma linha do array (ignora comentário após #)
_ip() { echo "$1" | awk '{print $1}'; }

# CIDRs GitHub hooks (T-345) — arquivo versionado, sync via sync_github_webhook_ips.sh
_load_github_webhook_cidrs() {
    local cidrs=()
    if [[ -f "$GITHUB_WEBHOOK_IPS_FILE" ]]; then
        while IFS= read -r line; do
            line="${line%%#*}"
            line="${line// /}"
            [[ -z "$line" ]] && continue
            cidrs+=("$line")
        done <"$GITHUB_WEBHOOK_IPS_FILE"
    fi
    printf '%s\n' "${cidrs[@]}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Gera o script UFW completo que será executado remotamente
# ─────────────────────────────────────────────────────────────────────────────
_build_ufw_script() {
    cat <<'HEREDOC_HEADER'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
echo ""
echo "══ Configurando UFW ═══════════════════════════════════════════"
HEREDOC_HEADER

    # Instalar UFW se não existir
    cat <<'HEREDOC_INSTALL'
if ! command -v ufw &>/dev/null; then
    echo "📦 Instalando UFW..."
    apt-get install -y -qq ufw
fi
HEREDOC_INSTALL

    # Reset e defaults
    cat <<'HEREDOC_DEFAULTS'
echo "🔄 Resetando regras existentes..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing
# FORWARD: manter ACCEPT para CNI do Kubernetes (kube-proxy gerencia via iptables)
sed -i 's/^DEFAULT_FORWARD_POLICY=.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
echo "✔  Defaults: deny incoming, allow outgoing, allow forward"
HEREDOC_DEFAULTS

    # Loopback + K8s pod CIDRs (sempre permitido)
    cat <<'HEREDOC_INTERNAL'
ufw allow in on lo comment "loopback"
ufw allow from 10.0.0.0/8 comment "k8s-pods-services" >/dev/null
ufw allow from 172.16.0.0/12 comment "k8s-pods-alt" >/dev/null
echo "✔  Tráfego interno (lo, 10.x, 172.x): liberado"
HEREDOC_INTERNAL

    # SSH: porta 22 aberta para qualquer origem (safety net)
    cat <<'HEREDOC_SSH'
ufw allow 22/tcp comment "ssh-open" >/dev/null
echo "✔  Porta 22/tcp: aberta para qualquer origem (safety net)"
HEREDOC_SSH

    # Admin IPs: 80, 443, 6443
    echo ""
    echo "echo \"\""
    echo "echo \"━━ ADMIN IPs (80/443/6443) ━━━━━━━━━━━━━━━━━━━━━━\""
    for entry in "${ADMIN_IPS[@]}"; do
        local ip comment
        ip="$(_ip "$entry")"
        comment="${entry#*#}"
        comment="${comment## }"
        cat <<HEREDOC_ADMIN
ufw allow from ${ip} to any port 80  comment "admin-ingress-http" >/dev/null
ufw allow from ${ip} to any port 443 comment "admin-ingress-https" >/dev/null
ufw allow from ${ip} to any port 6443 comment "admin-kube-api" >/dev/null
echo "  ✔  ${ip}  # ${comment}"
HEREDOC_ADMIN
    done

    # Ingress IPs: 80 e 443 apenas
    echo ""
    echo "echo \"\""
    echo "echo \"━━ INGRESS IPs (80/443 apenas) ━━━━━━━━━━━━━━━━━━\""
    for entry in "${INGRESS_IPS[@]}"; do
        local ip comment
        ip="$(_ip "$entry")"
        comment="${entry#*#}"
        comment="${comment## }"
        cat <<HEREDOC_INGRESS
ufw allow from ${ip} to any port 80  comment "ingress-http" >/dev/null
ufw allow from ${ip} to any port 443 comment "ingress-https" >/dev/null
echo "  ✔  ${ip}  # ${comment}"
HEREDOC_INGRESS
    done

    # Tailscale overlay: ingress HTTPS from tailnet (T-320e)
    echo ""
    echo "echo \"\""
    echo "echo \"━━ TAILSCALE (${TAILSCALE_CIDR}) ━━━━━━━━━━━━━━━━━━━\""
    cat <<HEREDOC_TS
ufw allow from ${TAILSCALE_CIDR} to any port 80  comment "tailscale-ingress-http" >/dev/null
ufw allow from ${TAILSCALE_CIDR} to any port 443 comment "tailscale-ingress-https" >/dev/null
ufw allow from ${TAILSCALE_CIDR} to any port 18443 comment "tailscale-fleet-ops-gateway" >/dev/null
echo "  ✔  ${TAILSCALE_CIDR} → 80/443/18443"
HEREDOC_TS

    # GitHub webhooks → Jenkins :443 (T-345)
    echo ""
    echo "echo \"\""
    echo "echo \"━━ GITHUB WEBHOOKS (:443) ━━━━━━━━━━━━━━━━━━━━━━━\""
    while IFS= read -r cidr; do
        [[ -z "$cidr" ]] && continue
        cat <<HEREDOC_GH
ufw allow from ${cidr} to any port 443 comment "github-webhook" >/dev/null
echo "  ✔  ${cidr} → 443 (github-webhook)"
HEREDOC_GH
    done < <(_load_github_webhook_cidrs)

    # node_exporter :9100 — só IPs OCI (T-320b)
    echo ""
    echo "echo \"\""
    echo "echo \"━━ PROMETHEUS SCRAPE (:9100) ━━━━━━━━━━━━━━━━━━━━\""
    for entry in "${METRICS_IPS[@]}"; do
        local ip comment
        ip="$(_ip "$entry")"
        comment="${entry#*#}"
        comment="${comment## }"
        cat <<HEREDOC_METRICS
ufw allow from ${ip} to any port 9100 proto tcp comment "oci-prometheus-scrape" >/dev/null
echo "  ✔  ${ip}:9100  # ${comment}"
HEREDOC_METRICS
    done

    # Fleet Copilot: Ollama must stay localhost-only (T-321b)
    cat <<'HEREDOC_OLLAMA'
ufw deny 11434/tcp comment "ollama-localhost-only" >/dev/null 2>&1 || true
echo "✔  11434/tcp: deny (Ollama localhost only)"
HEREDOC_OLLAMA

    # Fleet-ops-gateway :8443 from OCI/Hetzner ingress IPs (fallback sem Tailscale)
    echo ""
    echo "echo \"\""
    echo "echo \"━━ FLEET OPS GATEWAY (:18443) ━━━━━━━━━━━━━━━━━━\""
    for entry in "${ADMIN_IPS[@]}" "${INGRESS_IPS[@]}"; do
        local ip comment
        ip="$(_ip "$entry")"
        comment="${entry#*#}"
        comment="${comment## }"
        cat <<HEREDOC_FLEET
ufw allow from ${ip} to any port 18443 proto tcp comment "fleet-ops-gateway" >/dev/null
echo "  ✔  ${ip}:18443  # ${comment}"
HEREDOC_FLEET
    done

    # NOTA: porta 80 NÃO é aberta permanentemente.
    # A renovação HTTP-01 do cert-manager é gerenciada pelo serviço
    # cert-renew-ufw (systemd timer diário), que abre 80 temporariamente,
    # aguarda o cert ficar Ready e fecha em seguida.
    # Ver: components/ssdnodes/cert-renew-ufw/

    # Habilitar
    cat <<'HEREDOC_ENABLE'
echo ""
echo "🔥 Habilitando UFW..."
ufw --force enable >/dev/null
echo ""
echo "══ Status final ═══════════════════════════════════════════════"
ufw status numbered
echo ""
echo "✅ UFW configurado com sucesso."
HEREDOC_ENABLE
}

# ─────────────────────────────────────────────────────────────────────────────
# ACTIONS
# ─────────────────────────────────────────────────────────────────────────────
action_status() {
    _head "Status UFW em $TARGET_HOST"
    $_SSH "$TARGET_HOST" "
        if command -v ufw &>/dev/null; then
            echo '--- UFW status ---'
            ufw status verbose 2>/dev/null
            echo ''
            echo '--- Portas abertas (ss) ---'
            ss -tlnp | grep -E 'LISTEN' | awk '{print \$4}' | sort -u
        else
            echo '⚠  UFW não instalado em $TARGET_HOST'
        fi
    " 2>/dev/null || _err "Falha ao conectar em $TARGET_HOST"
}

action_apply() {
    _head "Aplicando regras UFW em $TARGET_HOST"
    _warn "Porta 22 permanece aberta para qualquer origem (safety net)."
    echo ""

    local ufw_script
    ufw_script="$(_build_ufw_script)"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        _info "--- DRY RUN: script que seria executado remotamente ---"
        echo "$ufw_script"
        return 0
    fi

    echo "$ufw_script" | $_SSH "$TARGET_HOST" "sudo bash" 2>/dev/null \
        && _ok "Regras aplicadas com sucesso em $TARGET_HOST" \
        || { _err "Falha ao aplicar regras em $TARGET_HOST"; exit 1; }
}

action_dry_run() {
    _head "DRY RUN — Script UFW para $TARGET_HOST"
    DRY_RUN=true action_apply
}

action_disable() {
    _head "⚠️  Desabilitando UFW em $TARGET_HOST"
    _warn "Isso abrirá TODOS os ports ao mundo. Apenas para emergência."
    read -rp "Confirmar? (sim/N): " confirm
    [[ "$confirm" != "sim" ]] && { echo "Cancelado."; return 0; }
    $_SSH "$TARGET_HOST" "sudo ufw disable" 2>/dev/null \
        && _ok "UFW desabilitado em $TARGET_HOST" \
        || _err "Falha ao desabilitar UFW"
}

# ─────────────────────────────────────────────────────────────────────────────
# Modo interativo (quando chamado sem --action da TUI ou diretamente)
# ─────────────────────────────────────────────────────────────────────────────
action_interactive() {
    _head "Firewall UFW Manager — $TARGET_HOST"

    local menu_items
    menu_items="$(printf '%s\n' \
        "📊 Status — ver regras ativas" \
        "🔥 Aplicar — resetar e aplicar todas as regras" \
        "🔍 Dry Run — mostrar script sem executar" \
        "⛔ Desabilitar UFW (emergência)" \
        "↩  Voltar")"

    local selected
    selected=$(echo "$menu_items" | "$FZF_BIN" \
        --height=40% --layout=reverse --border \
        --prompt="UFW Manager ($TARGET_HOST) > " \
        --header="Firewall — ssdnodes-monstro (22/tcp: SEMPRE ABERTO)") || true

    [[ -z "$selected" ]] && return 0

    case "${selected:0:2}" in
        "📊") action_status ;;
        "🔥") action_apply ;;
        "🔍") action_dry_run ;;
        "⛔") action_disable ;;
        "↩ ") return 0 ;;
    esac

    echo ""
    read -rp "Pressione Enter para continuar..." _dummy || true
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────
_parse_args "$@"

case "$ACTION" in
    "status")   action_status ;;
    "apply")    action_apply ;;
    "dry-run")  action_dry_run ;;
    "disable")  action_disable ;;
    "")         action_interactive ;;
esac
