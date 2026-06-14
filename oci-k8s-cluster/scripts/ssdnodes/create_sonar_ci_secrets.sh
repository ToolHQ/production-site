#!/usr/bin/env bash
# create_sonar_ci_secrets.sh — imprime YAML de Secrets Sonar/Postgres (nunca commitar valores).
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./oci-k8s-cluster/scripts/ssdnodes/create_sonar_ci_secrets.sh \
    --postgres-password '...' \
    [--sonar-admin-password '...'] \
    [--sonar-monitoring-passcode '...']

Imprime YAML para kubectl apply -f - no cluster SSDNodes.
EOF
}

PG_PASS=""
SONAR_ADMIN=""
MON_PASS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --postgres-password) PG_PASS="$2"; shift 2 ;;
  --sonar-admin-password) SONAR_ADMIN="$2"; shift 2 ;;
  --sonar-monitoring-passcode) MON_PASS="$2"; shift 2 ;;
  -h | --help) usage; exit 0 ;;
  *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$PG_PASS" ]] || {
  echo "❌ --postgres-password obrigatório" >&2
  exit 2
}

SONAR_ADMIN="${SONAR_ADMIN:-$(openssl rand -base64 18 | tr -d '/+=' | head -c 24)}"
MON_PASS="${MON_PASS:-$(openssl rand -hex 16)}"

cat <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: sonarqube-db-credentials
  namespace: sonarqube-db
type: Opaque
stringData:
  postgres-password: ${PG_PASS}
  password: ${PG_PASS}
---
apiVersion: v1
kind: Secret
metadata:
  name: sonarqube-db-credentials
  namespace: sonarqube
type: Opaque
stringData:
  password: ${PG_PASS}
---
apiVersion: v1
kind: Secret
metadata:
  name: sonarqube-monitoring-passcode
  namespace: sonarqube
type: Opaque
stringData:
  SONAR_WEB_SYSTEMPASSCODE: ${MON_PASS}
EOF

echo "# Sonar admin inicial: defina após primeiro login ou via helm --set (não persistido aqui)." >&2
echo "# Jenkins Sonar token: crie em Sonar UI → My Account → Tokens → Secret jenkins/sonar-token" >&2
