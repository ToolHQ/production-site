#!/usr/bin/env bash
# create_n8n_secret.sh — imprime Secret n8n-credentials (nunca commitar valores).
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  ./oci-k8s-cluster/scripts/ssdnodes/create_n8n_secret.sh \
    [--encryption-key '32+ chars'] \
    [--basic-auth-user 'admin'] \
    [--basic-auth-password '...']

Imprime YAML para: kubectl apply -f - (cluster SSDNodes)
EOF
}

ENC_KEY=""
BASIC_USER="n8n-admin"
BASIC_PASS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --encryption-key) ENC_KEY="$2"; shift 2 ;;
  --basic-auth-user) BASIC_USER="$2"; shift 2 ;;
  --basic-auth-password) BASIC_PASS="$2"; shift 2 ;;
  -h | --help) usage; exit 0 ;;
  *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

ENC_KEY="${ENC_KEY:-$(openssl rand -hex 32)}"
BASIC_PASS="${BASIC_PASS:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)}"

cat <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: n8n-credentials
  namespace: n8n
type: Opaque
stringData:
  N8N_ENCRYPTION_KEY: ${ENC_KEY}
  N8N_BASIC_AUTH_USER: ${BASIC_USER}
  N8N_BASIC_AUTH_PASSWORD: ${BASIC_PASS}
EOF

echo "# Basic auth user: ${BASIC_USER}" >&2
echo "# Basic auth pass: ${BASIC_PASS}  (salve em ~/ssdnodes-n8n-credentials.txt)" >&2
