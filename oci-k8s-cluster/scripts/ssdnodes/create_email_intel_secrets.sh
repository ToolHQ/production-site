#!/usr/bin/env bash
# create_email_intel_secrets.sh — Secrets Postgres email-intelligence (T-362a)
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./oci-k8s-cluster/scripts/ssdnodes/create_email_intel_secrets.sh

Imprime YAML para kubectl apply -f - (namespace email-intelligence).
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage && exit 0

PG_PASS="${POSTGRES_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"
MIGRATOR_PASS="${MIGRATOR_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"
N8N_APP_PASS="${N8N_APP_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"
PGCRYPTO_KEY="${PGCRYPTO_KEY:-$(openssl rand -hex 32)}"

cat <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  name: email-intelligence
  labels:
    kubernetes.io/metadata.name: email-intelligence
---
apiVersion: v1
kind: Secret
metadata:
  name: email-intelligence-db-credentials
  namespace: email-intelligence
type: Opaque
stringData:
  postgres-password: ${PG_PASS}
  migrator-password: ${MIGRATOR_PASS}
  password: ${MIGRATOR_PASS}
  n8n-app-password: ${N8N_APP_PASS}
  pgcrypto-key: ${PGCRYPTO_KEY}
EOF

echo "# Salve em ~/ssdnodes-email-intelligence-credentials.txt (chmod 600)" >&2
echo "# n8n_app DB password: ${N8N_APP_PASS}" >&2
echo "# pgcrypto-key: ${PGCRYPTO_KEY}" >&2
