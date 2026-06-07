#!/usr/bin/env bash
# setup_jenkins_ci_jobs.sh — Secret K8s + helm upgrade Jenkins CI (T-341)
#
# Cria credenciais (sonar-token, github-pat) via Secret + JCasC Job DSL multibranch.
# Script Console desabilitado no Jenkins hardened — não usa /scriptText.
#
# Uso:
#   bash oci-k8s-cluster/scripts/ssdnodes/setup_jenkins_ci_jobs.sh
#   bash oci-k8s-cluster/scripts/ssdnodes/setup_jenkins_ci_jobs.sh --update-home-creds
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPONENTS_DIR="$REPO_ROOT/components/ssdnodes"

JENKINS_URL="${JENKINS_URL:-https://jenkins.ssdnodes.dnor.io}"
SONAR_URL="${SONAR_URL:-https://sonar.ssdnodes.dnor.io}"
SONAR_USER="${SONAR_USER:-admin}"
JOB_NAME="${JENKINS_JOB_NAME:-production-site}"
REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
SECRET_NAME="${JENKINS_CI_SECRET_NAME:-jenkins-ci-credentials}"
CREDS_FILE="${SSD_NODES_CI_CREDS:-${HOME}/ssdnodes-ci-platform-credentials.txt}"
DRY_RUN=false
UPDATE_HOME=false

usage() {
  cat <<EOF
Setup CI Jenkins (T-341):
  1. Token Sonar + projeto production-site
  2. Secret ${SECRET_NAME} → JCasC credentials
  3. helm upgrade (job-dsl multibranch ${JOB_NAME})

Requer: gh auth login
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=true; shift ;;
  --update-home-creds) UPDATE_HOME=true; shift ;;
  -h | --help) usage; exit 0 ;;
  *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

log() { echo "[setup-jenkins-ci] $*"; }
kubectl_ssh() { ssh -o ConnectTimeout=15 "$REMOTE_HOST" kubectl "$@"; }

if [[ -z "${SONAR_ADMIN_PASSWORD:-}" && -f "$CREDS_FILE" ]]; then
  SONAR_ADMIN_PASSWORD=$(awk '/^  SonarQube$/,/^  PostgreSQL/' "$CREDS_FILE" \
    | awk -F: '/^  Senha/ {gsub(/^[[:space:]]+/, "", $2); print $2; exit}' || true)
fi

if [[ -z "${SONAR_TOKEN:-}" ]] || [[ ${#SONAR_TOKEN} -lt 20 ]]; then
  [[ -n "${SONAR_ADMIN_PASSWORD:-}" ]] || {
    echo "❌ SONAR_ADMIN_PASSWORD ou senha Sonar em $CREDS_FILE" >&2
    exit 2
  }
  TOKEN_NAME="jenkins-citools-$(date +%Y%m%d-%H%M)"
  log "Gerando token Sonar ($TOKEN_NAME)..."
  SONAR_TOKEN=$(curl -fsS -u "${SONAR_USER}:${SONAR_ADMIN_PASSWORD}" -X POST \
    "${SONAR_URL}/api/user_tokens/generate?name=${TOKEN_NAME}" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
  [[ ${#SONAR_TOKEN} -ge 20 ]] || {
    echo "❌ token Sonar inválido (len=${#SONAR_TOKEN}) — verifique SONAR_ADMIN_PASSWORD" >&2
    exit 2
  }
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  GITHUB_TOKEN=$(gh auth token 2>/dev/null || true)
  [[ -n "${GITHUB_TOKEN:-}" ]] || {
    echo "❌ gh auth login ou GITHUB_TOKEN" >&2
    exit 2
  }
fi

if [[ -z "${GITHUB_WEBHOOK_SECRET:-}" ]]; then
  GITHUB_WEBHOOK_SECRET=$(openssl rand -hex 32)
  log "Gerado GITHUB_WEBHOOK_SECRET (salve após configure_github_ci_protection.sh se usar secret externo)"
fi

[[ "$DRY_RUN" == true ]] && { log "[dry-run] OK"; exit 0; }

curl -fsS -u "${SONAR_USER}:${SONAR_ADMIN_PASSWORD}" -X POST \
  "${SONAR_URL}/api/projects/create?project=production-site&name=production-site&mainBranch=main" \
  >/dev/null 2>&1 || true

log "Secret ${SECRET_NAME}..."
kubectl_ssh create namespace jenkins --dry-run=client -o yaml | kubectl_ssh apply -f -
kubectl_ssh create secret generic "$SECRET_NAME" -n jenkins \
  --from-literal=sonar-token="$SONAR_TOKEN" \
  --from-literal=github-pat="$GITHUB_TOKEN" \
  --from-literal=github-webhook-secret="$GITHUB_WEBHOOK_SECRET" \
  --dry-run=client -o yaml | kubectl_ssh apply -f -

log "Helm upgrade jenkins..."
scp -q "$COMPONENTS_DIR/jenkins-values.yaml" "$REMOTE_HOST:/tmp/ssdnodes-components/jenkins-values.yaml"
ssh "$REMOTE_HOST" bash <<REMOTE
set -euo pipefail
JENKINS_HELM_CHART_VERSION="${JENKINS_HELM_CHART_VERSION:-5.9.22}"
helm repo add jenkins https://charts.jenkins.io 2>/dev/null || true
helm repo update
helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --version "\${JENKINS_HELM_CHART_VERSION}" \
  --values /tmp/ssdnodes-components/jenkins-values.yaml \
  --wait --timeout 20m
kubectl rollout status statefulset/jenkins -n jenkins --timeout=600s
REMOTE

bash "$SCRIPT_DIR/seed_jenkins_ci_job.sh"
bash "$SCRIPT_DIR/seed_jenkins_deploy_job.sh"

for _ in $(seq 1 36); do
  curl -fsSI --max-time 10 "${JENKINS_URL}/login" >/dev/null 2>&1 && break
  sleep 5
done

if [[ "$UPDATE_HOME" == true && -f "$CREDS_FILE" ]]; then
  umask 077
  grep -q 'Token CI (jenkins-citools)' "$CREDS_FILE" && \
    sed -i '/Token CI (jenkins-citools)/,$d' "$CREDS_FILE" 2>/dev/null || true
  cat >>"$CREDS_FILE" <<EOF

Token CI (jenkins-citools):
  Valor                 : ${SONAR_TOKEN}
  Jenkins credential id : sonar-token
  GitHub credential id  : github-pat
  Job multibranch       : ${JENKINS_URL}/job/${JOB_NAME}/
EOF
  log "Atualizado $CREDS_FILE"
fi

log "✓ ${JENKINS_URL}/job/${JOB_NAME}/"
