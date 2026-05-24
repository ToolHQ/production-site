#!/usr/bin/env bash
# Gera bundle + one-liner para bootstrap manual na EC2 (console AWS / SSM).
# Use quando o WSL ainda não tem SSH para root@<host>.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

NODE_ID=""
HOST=""
OPERATOR_IP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NODE_ID="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --operator-ip) OPERATOR_IP="$2"; shift 2 ;;
    -h|--help)
      echo "Uso: $0 --name aws-ec2-fleet-01 --host 3.236.249.77 [--operator-ip IP]"
      exit 0
      ;;
    *) fail "Argumento desconhecido: $1" ;;
  esac
done

[[ -n "$NODE_ID" && -n "$HOST" ]] || fail "--name e --host são obrigatórios"

mapfile -t DEFAULTS < <(read_registry_defaults)
OPS_USER="${DEFAULTS[0]:-dnorio-fleet}"
METRICS_PORT="${DEFAULTS[1]:-9100}"

if [[ -z "$OPERATOR_IP" ]]; then
  OPERATOR_IP="$(detect_operator_public_ip || true)"
fi

OCI_IPS="$(python3 - "$REGISTRY_PATH" <<'PY'
import yaml, sys
data = yaml.safe_load(open(sys.argv[1]))
print(",".join(data.get("scrape_sources", {}).get("oci_k8s_public_ips", [])))
PY
)"

KEY_FILE="$(expand_path "~/.ssh/aws-fleet-${NODE_ID}.ed25519")"
PUB_FILE="${KEY_FILE}.pub"
BUNDLE_DIR="/tmp/aws-fleet-${NODE_ID}-bundle"

require_cmd ssh-keygen
mkdir -p "$BUNDLE_DIR"

if [[ ! -f "$KEY_FILE" ]]; then
  ssh-keygen -t ed25519 -f "$KEY_FILE" -C "${OPS_USER}@${NODE_ID}@production-site" -N ""
  chmod 600 "$KEY_FILE"
fi

cp "$REMOTE_BOOTSTRAP" "$BUNDLE_DIR/remote-bootstrap.sh"
cp "$PUB_FILE" "$BUNDLE_DIR/bootstrap.pub"
tar -C "$BUNDLE_DIR" -czf "/tmp/aws-fleet-${NODE_ID}.tar.gz" remote-bootstrap.sh bootstrap.pub

PUB_INLINE="$(cat "$PUB_FILE")"

cat <<EOF
╔══════════════════════════════════════════════════════════════╗
║  Bootstrap manual — cole NA EC2 como root (console AWS)      ║
╚══════════════════════════════════════════════════════════════╝

1) Security Group: libere TCP/22 para ${OPERATOR_IP:-SEU_IP}/32

2) Copie o bundle do WSL para a EC2:

scp /tmp/aws-fleet-${NODE_ID}.tar.gz root@${HOST}:/tmp/
ssh root@${HOST} 'mkdir -p /tmp/aws-fleet && tar -xzf /tmp/aws-fleet-${NODE_ID}.tar.gz -C /tmp/aws-fleet'

3) Na EC2 (root), execute o bootstrap:

sudo OPS_USER='${OPS_USER}' METRICS_PORT='${METRICS_PORT}' \\
  OPERATOR_SSH_IP='${OPERATOR_IP}' OCI_SCRAPE_IPS_CSV='${OCI_IPS}' \\
  METADATA_OUT='/tmp/aws-fleet-metadata.json' \\
  bash /tmp/aws-fleet/remote-bootstrap.sh /tmp/aws-fleet/bootstrap.pub

4) Security Group AWS — também adicione regras TCP/9100 para:
   ${OCI_IPS//,/ , }

5) No WSL, finalize registro (sem bootstrap):

./scripts/aws-fleet/provision-aws-external-node.sh \\
  --host ${HOST} \\
  --instance-id i-XXXXXXXXX \\
  --name ${NODE_ID} \\
  --ssh-user ${OPS_USER} \\
  --skip-bootstrap \\
  --apply

Chave privada (local): ${KEY_FILE}
Bundle tar: /tmp/aws-fleet-${NODE_ID}.tar.gz

EOF

ok "Bundle pronto: /tmp/aws-fleet-${NODE_ID}.tar.gz"
