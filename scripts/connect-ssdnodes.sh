#!/bin/bash
# =============================================================================
# SSD Nodes - Quick Connect Script
# =============================================================================
# Uso:
#   ./scripts/connect-ssdnodes.sh          # SSH interativo
#   ./scripts/connect-ssdnodes.sh --cmd "uptime"  # Executar comando remoto
#   ./scripts/connect-ssdnodes.sh --kube            # Acessar cluster K8s
# =============================================================================

set -euo pipefail

SSD_HOST="ssdnodes-6a12f10c9ef11"
SSD_IP="104.225.218.78"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    echo -e "${YELLOW}Uso:${NC}"
    echo "  $0                    # SSH interativo"
    echo "  $0 --cmd \"uptime\"     # Executar comando remoto"
    echo "  $0 --kube             # Acessar cluster K8s"
    echo "  $0 --status           # Relatório rápido do servidor"
    echo "  $0 --help             # Esta mensagem"
    exit 0
}

# Verificar se SSH config está instalado
check_ssh_config() {
    if ! grep -q "$SSD_HOST" ~/.ssh/config 2>/dev/null; then
        echo -e "${YELLOW}⚠ SSH config não encontrado. Instalando...${NC}"
        bash oci-k8s-cluster/scripts/ssdnodes/install_ssdnodes_ssh_config.sh
    fi
}

# Relatório rápido do servidor
show_status() {
    echo -e "${GREEN}=== SSD Nodes Status ===${NC}"
    ssh "$SSD_HOST" <<'REMOTE_EOF'
echo "Hostname:  $(hostname)"
echo "Uptime:    $(uptime -p)"
echo "CPU:       $(nproc) cores | Load: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
echo "Memory:    $(free -h | awk '/^Mem:/{print $3 "/" $2 " used"}')"
echo "Disk:      $(df -h / | awk 'NR==2{print $3 "/" $2 " used (" $5 ")"}')"
echo "K8s Node:  $(kubectl get nodes --no-headers 2>/dev/null | awk '{print $1, $2, $5}' || echo 'N/A')"
echo "Tailscale: $(tailscale ip -4 2>/dev/null || echo 'N/A')"
REMOTE_EOF
}

# Acessar cluster K8s
access_kube() {
    echo -e "${GREEN}=== SSD Nodes Kubernetes Cluster ===${NC}"
    echo "Kubeconfig: ~/.kube/ssdnodes.yaml"
    echo ""
    ssh "$SSD_HOST" "export KUBECONFIG=~/.kube/ssdnodes.yaml && kubectl get nodes"
    echo ""
    echo "Para usar localmente:"
    echo "  export KUBECONFIG=~/.kube/ssdnodes.yaml"
    echo "  kubectl get nodes"
}

# Main
case "${1:---status}" in
    --cmd)
        check_ssh_config
        shift
        ssh "$SSD_HOST" "$*"
        ;;
    --kube)
        check_ssh_config
        access_kube
        ;;
    --status)
        check_ssh_config
        show_status
        ;;
    --help|-h)
        usage
        ;;
    *)
        check_ssh_config
        ssh "$SSD_HOST" "$@" || ssh "$SSD_HOST"
        ;;
esac
