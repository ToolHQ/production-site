#!/usr/bin/env bash
# export_ci_credentials.sh — Gera arquivo local com credenciais CI SSDNodes (T-341).
# Nunca commitar o arquivo de saída.
#
# Uso:
#   bash oci-k8s-cluster/scripts/ssdnodes/export_ci_credentials.sh
#   bash oci-k8s-cluster/scripts/ssdnodes/export_ci_credentials.sh --output ~/ssdnodes-ci-platform-credentials.txt
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
OUTPUT="${HOME}/ssdnodes-ci-platform-credentials.txt"
SONAR_URL="${SONAR_URL:-https://sonar.ssdnodes.dnor.io}"
JENKINS_URL="${JENKINS_URL:-https://jenkins.ssdnodes.dnor.io}"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --output) OUTPUT="$2"; shift 2 ;;
  --host) REMOTE_HOST="$2"; shift 2 ;;
  -h | --help)
    echo "Uso: $0 [--output PATH] [--host SSH_HOST]"
    exit 0
    ;;
  *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

read -r JENKINS_PASS PG_PASS MON_PASS <<EOF
$(ssh -o ConnectTimeout=15 -o BatchMode=yes "$REMOTE_HOST" bash <<'REMOTE'
set -euo pipefail
jp=$(kubectl exec -n jenkins svc/jenkins -c jenkins -- cat /run/secrets/additional/chart-admin-password 2>/dev/null || echo "N/A")
pg=$(kubectl get secret sonarqube-db-credentials -n sonarqube-db -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "N/A")
mp=$(kubectl get secret sonarqube-monitoring-passcode -n sonarqube -o jsonpath='{.data.SONAR_WEB_SYSTEMPASSCODE}' 2>/dev/null | base64 -d || echo "N/A")
printf '%s\n%s\n%s\n' "$jp" "$pg" "$mp"
REMOTE
)
EOF

GENERATED_AT="$(date -Iseconds)"

umask 077
cat >"$OUTPUT" <<EOF
# SSDNodes CI Platform — credenciais (T-341)
# Gerado: ${GENERATED_AT}
# Regenerar: bash oci-k8s-cluster/scripts/ssdnodes/export_ci_credentials.sh
# Permissões: chmod 600 (aplicado automaticamente)
# NÃO commitar este arquivo.

═══════════════════════════════════════════════════════════════
  URLs
═══════════════════════════════════════════════════════════════

SonarQube CE : ${SONAR_URL}
Jenkins LTS  : ${JENKINS_URL}

Validação rápida:
  curl -fsS ${SONAR_URL}/api/system/status
  curl -fsSI ${JENKINS_URL}/login

Harness:
  bash scripts/harness/validate_ssdnodes_ci.sh

═══════════════════════════════════════════════════════════════
  Jenkins
═══════════════════════════════════════════════════════════════

Usuário : admin
Senha   : ${JENKINS_PASS}

Segurança (JCasC):
  - allowsSignup: false
  - allowAnonymousRead: false

Obter senha novamente (cluster):
  ssh ${REMOTE_HOST} "kubectl exec -n jenkins svc/jenkins -c jenkins -- cat /run/secrets/additional/chart-admin-password"

═══════════════════════════════════════════════════════════════
  SonarQube
═══════════════════════════════════════════════════════════════

Primeiro login (padrão CE, se ainda não alterado):
  Usuário : admin
  Senha   : admin

Após login, altere a senha em My Account → Security.
Monitoring passcode (API interna / probes):
  ${MON_PASS}

forceAuthentication: true (API anônima retorna 401)

Token CI (criar manualmente):
  Sonar UI → My Account → Security → Generate Token
  → usar no Jenkins como credencial sonar-token

═══════════════════════════════════════════════════════════════
  PostgreSQL (interno — não exposto)
═══════════════════════════════════════════════════════════════

Host    : sonarqube-db-postgresql.sonarqube-db.svc.cluster.local:5432
Database: sonar
User    : sonar
Senha   : ${PG_PASS}

Acesso só de dentro do cluster (NetworkPolicy).

═══════════════════════════════════════════════════════════════
  TLS / UFW
═══════════════════════════════════════════════════════════════

Certs: cert-manager + letsencrypt-prod (HTTP-01)
Renovação: cert-renew-ufw.timer no host SSDNodes
Porta 80 global: fechada após emissão (allowlist IP + Tailscale)

EOF

chmod 600 "$OUTPUT"
echo "✓ Credenciais salvas em: $OUTPUT (chmod 600)"
