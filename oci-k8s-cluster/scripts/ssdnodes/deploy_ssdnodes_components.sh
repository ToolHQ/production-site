#!/usr/bin/env bash
# deploy_ssdnodes_components.sh
# Deploy de componentes adicionais no ssdnodes-monstro via Helm.
# Chamado pela TUI (k8s_ops_menu.sh) — não executar manualmente.
#
# Uso: deploy_ssdnodes_components.sh [dashboard|kubecost|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPONENTS_DIR="$SCRIPT_DIR/../components/ssdnodes"
REMOTE_HOST="ssdnodes-monstro"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[ssdnodes]${NC} $*"; }
warn() { echo -e "${YELLOW}[ssdnodes]${NC} $*"; }
err()  { echo -e "${RED}[ssdnodes]${NC} $*" >&2; }

TARGET="${1:-all}"

# ─── Copia manifests para o host remoto ──────────────────────────────────────
upload_manifests() {
  log "Enviando manifests para $REMOTE_HOST:/tmp/ssdnodes-components/ ..."
  ssh "$REMOTE_HOST" "mkdir -p /tmp/ssdnodes-components"
  scp -q "$COMPONENTS_DIR"/*.yaml "$REMOTE_HOST:/tmp/ssdnodes-components/"
}

# ─── Kubernetes Dashboard ─────────────────────────────────────────────────────
deploy_dashboard() {
  log "=== Kubernetes Dashboard ==="
  log "Baixando chart v7.14.0 (github.com/kubernetes-retired/dashboard)..."
  ssh "$REMOTE_HOST" bash << 'REMOTE'
set -euo pipefail
mkdir -p /tmp/helm-charts
curl -sL -o /tmp/helm-charts/kubernetes-dashboard-7.14.0.tgz \
  "https://github.com/kubernetes-retired/dashboard/releases/download/kubernetes-dashboard-7.14.0/kubernetes-dashboard-7.14.0.tgz"
echo "Chart baixado: $(du -h /tmp/helm-charts/kubernetes-dashboard-7.14.0.tgz)"

kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -

# Criar ServiceAccount admin-user para login com token (view-only — T-320d)
kubectl apply -f - <<SA
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
SA

helm upgrade --install kubernetes-dashboard /tmp/helm-charts/kubernetes-dashboard-7.14.0.tgz \
  --namespace kubernetes-dashboard \
  --values /tmp/ssdnodes-components/kubernetes-dashboard-values.yaml \
  --wait --timeout 5m

kubectl apply -f /tmp/ssdnodes-components/kubernetes-dashboard-ingress.yaml
echo "[dashboard] Ingress aplicado."
REMOTE
  log "Kubernetes Dashboard instalado ✓"
}

# ─── Kubecost ─────────────────────────────────────────────────────────────────
deploy_kubecost() {
  log "=== Kubecost Free Tier ==="
  ssh "$REMOTE_HOST" bash << 'REMOTE'
set -euo pipefail
helm repo add kubecost https://kubecost.github.io/cost-analyzer/ || true
helm repo update
kubectl create namespace kubecost --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --version 2.8.6 \
  --values /tmp/ssdnodes-components/kubecost-values.yaml \
  --wait --timeout 5m

kubectl apply -f /tmp/ssdnodes-components/kubecost-ingress.yaml
echo "[kubecost] Ingress aplicado."
REMOTE
  log "Kubecost instalado ✓"
}

# ─── Abrir porta 80 para emissão inicial de certs ────────────────────────────
open_port80_for_certs() {
  warn "Abrindo porta 80 temporariamente para HTTP-01 (Let's Encrypt)..."
  ssh "$REMOTE_HOST" "ufw allow 80/tcp comment 'cert-issue-temp'" 2>/dev/null || true
  log "Aguardando 90s para emissão dos certificados..."
  sleep 90
  local k8s_ready cost_ready
  k8s_ready=$(ssh "$REMOTE_HOST" "kubectl get cert -n kubernetes-dashboard kubernetes-dashboard-tls -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null || echo 'False'")
  cost_ready=$(ssh "$REMOTE_HOST" "kubectl get cert -n kubecost kubecost-tls -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null || echo 'False'")
  log "Cert k8s-dashboard: $k8s_ready | Cert kubecost: $cost_ready"
  if [[ "$k8s_ready" == "True" && "$cost_ready" == "True" ]]; then
    log "Ambos os certs emitidos — fechando porta 80."
    ssh "$REMOTE_HOST" "ufw delete allow 80/tcp" 2>/dev/null || true
  else
    warn "Certs ainda pendentes. A cert-renew-ufw.timer vai finalizar nas próximas 24h."
    warn "Porta 80 aberta — feche manualmente quando os certs estiverem READY:"
    warn "  ssh $REMOTE_HOST 'ufw delete allow 80/tcp'"
  fi
}

deploy_fleet_copilot() {
  log "=== Fleet Copilot (Ollama + gateway) ==="
  bash "$COMPONENTS_DIR/install_ollama.sh" --host "$REMOTE_HOST"
  bash "$COMPONENTS_DIR/fleet-copilot/install_fleet_ops_gateway.sh"
  bash "$SCRIPT_DIR/../scripts/hardening/ufw_manager.sh" --host "$REMOTE_HOST" --apply
  log "Fleet Copilot stack atualizado ✓"
}

# ─── Status ───────────────────────────────────────────────────────────────────
show_status() {
  log "=== Status pós-deploy ==="
  ssh "$REMOTE_HOST" bash << 'REMOTE'
echo "--- Pods ---"
kubectl get pods -n kubernetes-dashboard 2>/dev/null || echo "(sem namespace)"
kubectl get pods -n kubecost 2>/dev/null || echo "(sem namespace)"
echo "--- Ingresses ---"
kubectl get ingress -A 2>/dev/null
echo "--- Certificates ---"
kubectl get cert -A 2>/dev/null || true
REMOTE
}

# ─── Main ─────────────────────────────────────────────────────────────────────
upload_manifests

case "$TARGET" in
  dashboard) deploy_dashboard; open_port80_for_certs ;;
  kubecost)  deploy_kubecost; open_port80_for_certs ;;
  fleet-copilot) deploy_fleet_copilot ;;
  all)
    deploy_dashboard
    deploy_kubecost
    open_port80_for_certs
    ;;
  status)    show_status; exit 0 ;;
  *)
    err "Uso: $0 [dashboard|kubecost|fleet-copilot|all|status]"
    exit 1
    ;;
esac

show_status
log "Deploy concluído. Acesse:"
log "  https://k8s.ssdnodes.dnor.io   (Kubernetes Dashboard)"
log "  https://cost.ssdnodes.dnor.io  (Kubecost)"
