#!/usr/bin/env bash
# deploy_ssdnodes_components.sh
# Deploy de componentes adicionais no ssdnodes-monstro via Helm.
# Chamado pela TUI (k8s_ops_menu.sh) — não executar manualmente.
#
# Uso: deploy_ssdnodes_components.sh [dashboard|kubecost|sonarqube|jenkins|ci-platform|ci-status|n8n|email-intelligence|ollama-bridge|fleet-copilot|all|status]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPONENTS_DIR="$SCRIPT_DIR/../components/ssdnodes"
REMOTE_HOST="ssdnodes-monstro"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[ssdnodes]${NC} $*"; }
warn() { echo -e "${YELLOW}[ssdnodes]${NC} $*"; }
err()  { echo -e "${RED}[ssdnodes]${NC} $*" >&2; }

TARGET="${1:-all}"

# CI platform chart pins (T-342) — manter alinhado a components/ssdnodes/*-values.yaml
SONARQUBE_HELM_CHART_VERSION="${SONARQUBE_HELM_CHART_VERSION:-2026.3.1}"
JENKINS_HELM_CHART_VERSION="${JENKINS_HELM_CHART_VERSION:-5.9.22}"

# ─── Copia manifests para o host remoto ──────────────────────────────────────
upload_manifests() {
  log "Enviando manifests para $REMOTE_HOST:/tmp/ssdnodes-components/ ..."
  ssh "$REMOTE_HOST" "mkdir -p /tmp/ssdnodes-components/schema /tmp/ssdnodes-components/n8n"
  scp -q "$COMPONENTS_DIR"/*.yaml "$REMOTE_HOST:/tmp/ssdnodes-components/"
  scp -q "$COMPONENTS_DIR"/n8n/*.yaml "$REMOTE_HOST:/tmp/ssdnodes-components/n8n/" 2>/dev/null || true
  scp -q "$COMPONENTS_DIR"/n8n/schema/*.sql "$REMOTE_HOST:/tmp/ssdnodes-components/schema/"
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

# Criar ServiceAccount admin-user para login com token
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
  name: cluster-admin
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
# Args opcionais: namespace/certname (ex.: sonarqube/sonarqube-tls)
# Default (sem args): kubernetes-dashboard + kubecost
wait_certs_ready() {
	local max_wait="$1"
	shift
	local -a specs=("$@")
	local elapsed=0 all_ready spec ns name status
	while [[ "$elapsed" -lt "$max_wait" ]]; do
		all_ready=true
		for spec in "${specs[@]}"; do
			ns="${spec%%/*}"
			name="${spec#*/}"
			status=$(ssh "$REMOTE_HOST" "kubectl get cert '$name' -n '$ns' -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null || echo 'False'")
			log "  cert $ns/$name → $status"
			[[ "$status" == "True" ]] || all_ready=false
		done
		$all_ready && return 0
		sleep 10
		elapsed=$((elapsed + 10))
	done
	return 1
}

reset_stale_cert() {
	local ns="$1" name="$2"
	warn "Reset cert $name (namespace $ns) — order ACME stale"
	ssh "$REMOTE_HOST" bash -s "$ns" "$name" <<'REMOTE'
set -euo pipefail
ns="$1" name="$2"
kubectl delete cert "$name" -n "$ns" --ignore-not-found
kubectl delete certificaterequest -n "$ns" --all --ignore-not-found 2>/dev/null || true
kubectl delete order -n "$ns" --all --ignore-not-found 2>/dev/null || true
kubectl delete challenge -n "$ns" --all --ignore-not-found 2>/dev/null || true
REMOTE
}

open_port80_for_certs() {
	local -a specs=("$@")
	if [[ ${#specs[@]} -eq 0 ]]; then
		specs=(
			"kubernetes-dashboard/kubernetes-dashboard-tls"
			"kubecost/kubecost-tls"
		)
	fi

	warn "Abrindo porta 80 temporariamente para HTTP-01 (Let's Encrypt)..."
	ssh "$REMOTE_HOST" "ufw allow 80/tcp comment 'cert-issue-temp'" 2>/dev/null || true

	# Reaplicar ingress CI se existir (recria Certificate após reset)
	ssh "$REMOTE_HOST" bash <<'REMOTE'
set -euo pipefail
for f in sonarqube-ingress.yaml jenkins-ingress.yaml n8n-ingress.yaml kubernetes-dashboard-ingress.yaml kubecost-ingress.yaml; do
  [[ -f "/tmp/ssdnodes-components/$f" ]] && kubectl apply -f "/tmp/ssdnodes-components/$f" || true
done
REMOTE

	if ! wait_certs_ready 300 "${specs[@]}"; then
		# Retry sonar se presente na lista e ainda falhou
		local spec ns name st
		for spec in "${specs[@]}"; do
			[[ "$spec" == "sonarqube/sonarqube-tls" ]] || continue
			ns="${spec%%/*}"; name="${spec#*/}"
			st=$(ssh "$REMOTE_HOST" "kubectl get cert '$name' -n '$ns' -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null || echo False")
			if [[ "$st" != "True" ]]; then
				reset_stale_cert "$ns" "$name"
				ssh "$REMOTE_HOST" "kubectl apply -f /tmp/ssdnodes-components/sonarqube-ingress.yaml" 2>/dev/null || true
				wait_certs_ready 120 "${specs[@]}" || warn "Alguns certs ainda pendentes"
			fi
		done
	fi

	if wait_certs_ready 5 "${specs[@]}"; then
		log "Certs emitidos — fechando porta 80 global."
		ssh "$REMOTE_HOST" "ufw delete allow 80/tcp" 2>/dev/null || true
	else
		warn "Certs ainda pendentes. cert-renew-ufw.timer finaliza nas próximas 24h."
		warn "Porta 80 global aberta — feche quando READY:"
		warn "  ssh $REMOTE_HOST 'ufw delete allow 80/tcp'"
	fi
}

# ─── SonarQube CE + PostgreSQL (T-341) ───────────────────────────────────────
deploy_sonarqube() {
  log "=== SonarQube CE + PostgreSQL (T-341) ==="
  ssh "$REMOTE_HOST" bash << REMOTE
set -euo pipefail
SONARQUBE_HELM_CHART_VERSION="${SONARQUBE_HELM_CHART_VERSION}"
if ! kubectl get secret sonarqube-db-credentials -n sonarqube-db >/dev/null 2>&1; then
  echo "[sonar] ❌ Secret sonarqube-db-credentials ausente em sonarqube-db."
  echo "        Rode localmente:"
  echo "        bash oci-k8s-cluster/scripts/ssdnodes/create_sonar_ci_secrets.sh --postgres-password \"\$(openssl rand -base64 24)\" | ssh ssdnodes-6a12f10c9ef11 kubectl apply -f -"
  exit 1
fi

helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube 2>/dev/null || true
helm repo update

kubectl create namespace sonarqube-db --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace sonarqube --dry-run=client -o yaml | kubectl apply -f -

# JDBC secret deve existir também no namespace sonarqube (secrets são por namespace)
if ! kubectl get secret sonarqube-db-credentials -n sonarqube >/dev/null 2>&1; then
  kubectl get secret sonarqube-db-credentials -n sonarqube-db -o yaml | \
    sed 's/namespace: sonarqube-db/namespace: sonarqube/' | \
    grep -v 'resourceVersion:\|uid:\|creationTimestamp:' | \
    kubectl apply -f -
fi

helm upgrade --install sonarqube-db bitnami/postgresql \
  --namespace sonarqube-db \
  --version 15.5.38 \
  --values /tmp/ssdnodes-components/sonarqube-postgresql-values.yaml \
  --wait --timeout 15m

helm upgrade --install sonarqube sonarqube/sonarqube \
  --namespace sonarqube \
  --version "\${SONARQUBE_HELM_CHART_VERSION}" \
  --values /tmp/ssdnodes-components/sonarqube-values.yaml \
  --wait --timeout 20m

kubectl apply -f /tmp/ssdnodes-components/sonarqube-ingress.yaml
kubectl apply -f /tmp/ssdnodes-components/ci-network-policies.yaml
echo "[sonar] Ingress + NetworkPolicy aplicados."
REMOTE
  log "SonarQube instalado ✓"
}

# ─── Jenkins LTS (T-341) ─────────────────────────────────────────────────────
deploy_jenkins() {
  log "=== Jenkins LTS (T-341) ==="
  ssh "$REMOTE_HOST" bash << REMOTE
set -euo pipefail
JENKINS_HELM_CHART_VERSION="${JENKINS_HELM_CHART_VERSION}"
helm repo add jenkins https://charts.jenkins.io 2>/dev/null || true
helm repo update

kubectl create namespace jenkins --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --version "\${JENKINS_HELM_CHART_VERSION}" \
  --values /tmp/ssdnodes-components/jenkins-values.yaml \
  --wait --timeout 20m

kubectl apply -f /tmp/ssdnodes-components/jenkins-ingress.yaml
kubectl apply -f /tmp/ssdnodes-components/ci-network-policies.yaml
echo "[jenkins] Ingress + NetworkPolicy aplicados."
REMOTE
  log "Jenkins instalado ✓"
}

deploy_ci_platform() {
  deploy_sonarqube
  deploy_jenkins
  open_port80_for_certs sonarqube/sonarqube-tls jenkins/jenkins-tls
}

# ─── n8n automation (T-361) ───────────────────────────────────────────────────
deploy_n8n() {
  log "=== n8n self-hosted (T-361) ==="
  ssh "$REMOTE_HOST" bash << 'REMOTE'
set -euo pipefail
kubectl create namespace n8n --dry-run=client -o yaml | kubectl apply -f -

if ! kubectl get secret n8n-credentials -n n8n >/dev/null 2>&1; then
  echo "[n8n] ❌ Secret n8n-credentials ausente."
  echo "      bash oci-k8s-cluster/scripts/ssdnodes/create_n8n_secret.sh | ssh ssdnodes-6a12f10c9ef11 kubectl apply -f -"
  exit 1
fi

kubectl apply -f /tmp/ssdnodes-components/n8n-k8s.yaml
kubectl apply -f /tmp/ssdnodes-components/n8n-ingress.yaml
kubectl apply -f /tmp/ssdnodes-components/ci-network-policies.yaml
kubectl rollout status deployment/n8n -n n8n --timeout=5m

# Reemitir cert se challenge stale (DNS/UFW)
cert_st=$(kubectl get cert n8n-tls -n n8n -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo False)
if [[ "$cert_st" != "True" ]]; then
  echo "[n8n] Reset cert n8n-tls (ACME retry)..."
  ufw allow 80/tcp comment 'cert-issue-n8n' 2>/dev/null || true
  kubectl delete cert n8n-tls -n n8n --ignore-not-found
  kubectl delete challenge,order,certificaterequest -n n8n --all --ignore-not-found 2>/dev/null || true
  kubectl apply -f /tmp/ssdnodes-components/n8n-ingress.yaml
fi
echo "[n8n] Deploy + Ingress aplicados."
REMOTE
  open_port80_for_certs n8n/n8n-tls
  log "n8n instalado ✓"
}

# ─── Email intelligence Postgres (T-362a) ────────────────────────────────────
deploy_email_intelligence() {
  log "=== Email intelligence Postgres + RLS (T-362a) ==="
  ssh "$REMOTE_HOST" bash << 'REMOTE'
set -euo pipefail
if ! kubectl get secret email-intelligence-db-credentials -n email-intelligence >/dev/null 2>&1; then
  echo "[email-intel] ❌ Secret email-intelligence-db-credentials ausente."
  echo "      bash oci-k8s-cluster/scripts/ssdnodes/create_email_intel_secrets.sh | ssh ssdnodes-6a12f10c9ef11 kubectl apply -f -"
  exit 1
fi

helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update

kubectl create namespace email-intelligence --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install email-intelligence-postgresql bitnami/postgresql \
  --namespace email-intelligence \
  --version 15.5.38 \
  --values /tmp/ssdnodes-components/email-intelligence-postgresql-values.yaml \
  --wait --timeout 15m

kubectl apply -f /tmp/ssdnodes-components/email-intelligence-network-policies.yaml

kubectl create configmap email-intel-schema -n email-intelligence \
  --from-file=001_init.sql=/tmp/ssdnodes-components/schema/001_init.sql \
  --from-file=002_crypto_functions.sql=/tmp/ssdnodes-components/schema/002_crypto_functions.sql \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl delete job email-intel-schema-migrate -n email-intelligence --ignore-not-found
kubectl apply -f /tmp/ssdnodes-components/n8n/email-intelligence-migrate-job.yaml
kubectl wait --for=condition=complete job/email-intel-schema-migrate -n email-intelligence --timeout=5m

echo "[email-intel] Postgres + schema OK."
REMOTE
  log "Email intelligence Postgres instalado ✓"
}

# ─── Ollama host bridge (T-362c) ─────────────────────────────────────────────
deploy_ollama_bridge() {
  log "=== Ollama K8s bridge (T-362c) ==="
  bash "$(dirname "${BASH_SOURCE[0]}")/install_ollama_k8s_bridge.sh"
  ssh "$REMOTE_HOST" bash << 'REMOTE'
set -euo pipefail
kubectl apply -f /tmp/ssdnodes-components/n8n/ollama-host-service.yaml
kubectl apply -f /tmp/ssdnodes-components/email-intelligence-network-policies.yaml
echo "[ollama-bridge] Service+Endpoints aplicados no namespace n8n."
REMOTE
  log "Ollama bridge instalado ✓"
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
kubectl get pods -n n8n 2>/dev/null || echo "(sem namespace n8n)"
kubectl get pods -n email-intelligence 2>/dev/null || echo "(sem namespace email-intelligence)"
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
  sonarqube) deploy_sonarqube; open_port80_for_certs sonarqube/sonarqube-tls ;;
  jenkins)   deploy_jenkins; open_port80_for_certs jenkins/jenkins-tls ;;
  ci-platform) deploy_ci_platform ;;
  n8n)       deploy_n8n ;;
  email-intelligence) deploy_email_intelligence ;;
  ollama-bridge) deploy_ollama_bridge ;;
  fleet-copilot) deploy_fleet_copilot ;;
  all)
    deploy_dashboard
    deploy_kubecost
    open_port80_for_certs
    ;;
  *)
    err "Uso: $0 [dashboard|kubecost|sonarqube|jenkins|ci-platform|ci-status|n8n|email-intelligence|ollama-bridge|fleet-copilot|all|status]"
    exit 1
    ;;
esac

show_ci_status
log "Deploy concluído. Acesse:"
log "  https://k8s.ssdnodes.dnor.io    (Kubernetes Dashboard)"
log "  https://cost.ssdnodes.dnor.io   (Kubecost)"
log "  https://sonar.ssdnodes.dnor.io  (SonarQube CE — T-341)"
  log "  https://jenkins.ssdnodes.dnor.io (Jenkins — T-341)"
  log "  https://n8n.ssdnodes.dnor.io   (n8n — T-361)"
