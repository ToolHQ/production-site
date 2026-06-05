#!/usr/bin/env bash
# deploy_ssdnodes_components.sh
# Deploy de componentes adicionais no ssdnodes-monstro via Helm.
# Chamado pela TUI (k8s_ops_menu.sh) — não executar manualmente.
#
# Uso: deploy_ssdnodes_components.sh [dashboard|kubecost|sonarqube|jenkins|ci-platform|ci-status|fleet-copilot|all|status]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPONENTS_DIR="$SCRIPT_DIR/../components/ssdnodes"
REMOTE_HOST="ssdnodes-6a12f10c9ef11"

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
  local k8s_ready cost_ready sonar_ready jenkins_ready
  k8s_ready=$(ssh "$REMOTE_HOST" "kubectl get cert -n kubernetes-dashboard kubernetes-dashboard-tls -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null || echo 'False'")
  cost_ready=$(ssh "$REMOTE_HOST" "kubectl get cert -n kubecost kubecost-tls -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null || echo 'False'")
  sonar_ready=$(ssh "$REMOTE_HOST" "kubectl get cert -n sonarqube sonarqube-tls -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null || echo 'na'")
  jenkins_ready=$(ssh "$REMOTE_HOST" "kubectl get cert -n jenkins jenkins-tls -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null || echo 'na'")
  log "Certs — dashboard: $k8s_ready | kubecost: $cost_ready | sonar: $sonar_ready | jenkins: $jenkins_ready"
  if [[ "$k8s_ready" == "True" && "$cost_ready" == "True" ]]; then
    log "Ambos os certs emitidos — fechando porta 80."
    ssh "$REMOTE_HOST" "ufw delete allow 80/tcp" 2>/dev/null || true
  else
    warn "Certs ainda pendentes. A cert-renew-ufw.timer vai finalizar nas próximas 24h."
    warn "Porta 80 aberta — feche manualmente quando os certs estiverem READY:"
    warn "  ssh $REMOTE_HOST 'ufw delete allow 80/tcp'"
  fi
}

# ─── SonarQube CE + PostgreSQL (T-341) ───────────────────────────────────────
deploy_sonarqube() {
  log "=== SonarQube CE + PostgreSQL (T-341) ==="
  ssh "$REMOTE_HOST" bash << 'REMOTE'
set -euo pipefail
if ! kubectl get secret sonarqube-db-credentials -n sonarqube-db >/dev/null 2>&1; then
  echo "[sonar] ❌ Secret sonarqube-db-credentials ausente em sonarqube-db."
  echo "        Rode localmente:"
  echo "        bash oci-k8s-cluster/scripts/ssdnodes/create_sonar_ci_secrets.sh --postgres-password '...' | ssh ssdnodes-6a12f10c9ef11 kubectl apply -f -"
  exit 1
fi

helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube 2>/dev/null || true
helm repo update

kubectl create namespace sonarqube-db --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace sonarqube --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install sonarqube-db bitnami/postgresql \
  --namespace sonarqube-db \
  --version 15.5.38 \
  --values /tmp/ssdnodes-components/sonarqube-postgresql-values.yaml \
  --wait --timeout 10m

helm upgrade --install sonarqube sonarqube/sonarqube \
  --namespace sonarqube \
  --values /tmp/ssdnodes-components/sonarqube-values.yaml \
  --wait --timeout 15m

kubectl apply -f /tmp/ssdnodes-components/sonarqube-ingress.yaml
kubectl apply -f /tmp/ssdnodes-components/ci-network-policies.yaml
echo "[sonar] Ingress + NetworkPolicy aplicados."
REMOTE
  log "SonarQube instalado ✓"
}

# ─── Jenkins LTS (T-341) ─────────────────────────────────────────────────────
deploy_jenkins() {
  log "=== Jenkins LTS (T-341) ==="
  ssh "$REMOTE_HOST" bash << 'REMOTE'
set -euo pipefail
helm repo add jenkins https://charts.jenkins.io 2>/dev/null || true
helm repo update

kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --version 5.7.10 \
  --values /tmp/ssdnodes-components/jenkins-values.yaml \
  --wait --timeout 15m

kubectl apply -f /tmp/ssdnodes-components/jenkins-ingress.yaml
kubectl apply -f /tmp/ssdnodes-components/ci-network-policies.yaml
echo "[jenkins] Ingress + NetworkPolicy aplicados."
REMOTE
  log "Jenkins instalado ✓"
}

deploy_ci_platform() {
  deploy_sonarqube
  deploy_jenkins
  open_port80_for_certs
}

deploy_fleet_copilot() {
  log "=== Fleet Copilot (Ollama + gateway) ==="
  bash "$COMPONENTS_DIR/install_ollama.sh" --host "$REMOTE_HOST"
  bash "$COMPONENTS_DIR/fleet-copilot/install_fleet_ops_gateway.sh"
  bash "$COMPONENTS_DIR/fleet-copilot/setup_fleet_gateway_kubeconfig.sh" --host "$REMOTE_HOST" --verify
  bash "$SCRIPT_DIR/../scripts/hardening/ufw_manager.sh" --host "$REMOTE_HOST" --apply
  log "Fleet Copilot stack atualizado ✓"
}

# ─── Status ───────────────────────────────────────────────────────────────────
show_status() {
  log "=== Status pós-deploy ==="
  ssh "$REMOTE_HOST" bash << 'REMOTE'
echo "--- Pods ---"
kubectl get pods -n kubernetes-dashboard 2>/dev/null || echo "(sem namespace dashboard)"
kubectl get pods -n kubecost 2>/dev/null || echo "(sem namespace kubecost)"
kubectl get pods -n sonarqube-db 2>/dev/null || echo "(sem namespace sonarqube-db)"
kubectl get pods -n sonarqube 2>/dev/null || echo "(sem namespace sonarqube)"
kubectl get pods -n jenkins 2>/dev/null || echo "(sem namespace jenkins)"
echo "--- Ingresses ---"
kubectl get ingress -A 2>/dev/null
echo "--- Certificates ---"
kubectl get cert -A 2>/dev/null || true
REMOTE
}

show_ci_status() {
  show_status
  log "URLs CI (T-341):"
  log "  https://sonar.ssdnodes.dnor.io"
  log "  https://jenkins.ssdnodes.dnor.io"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "$TARGET" in
  status) show_status; exit 0 ;;
  ci-status) show_ci_status; exit 0 ;;
esac

upload_manifests

case "$TARGET" in
  dashboard) deploy_dashboard; open_port80_for_certs ;;
  kubecost)  deploy_kubecost; open_port80_for_certs ;;
  sonarqube) deploy_sonarqube; open_port80_for_certs ;;
  jenkins)   deploy_jenkins; open_port80_for_certs ;;
  ci-platform) deploy_ci_platform ;;
  fleet-copilot) deploy_fleet_copilot ;;
  all)
    deploy_dashboard
    deploy_kubecost
    open_port80_for_certs
    ;;
  *)
    err "Uso: $0 [dashboard|kubecost|sonarqube|jenkins|ci-platform|ci-status|fleet-copilot|all|status]"
    exit 1
    ;;
esac

show_ci_status
log "Deploy concluído. Acesse:"
log "  https://k8s.ssdnodes.dnor.io    (Kubernetes Dashboard)"
log "  https://cost.ssdnodes.dnor.io   (Kubecost)"
log "  https://sonar.ssdnodes.dnor.io  (SonarQube CE — T-341)"
log "  https://jenkins.ssdnodes.dnor.io (Jenkins — T-341)"
