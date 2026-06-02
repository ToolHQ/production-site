#!/usr/bin/env bash
# setup_fleet_gateway_kubeconfig.sh — T-321: SA view-only + kubeconfig em /etc/fleet-copilot/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$SCRIPT_DIR/rbac.yaml"
REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
KUBE_PATH="/etc/fleet-copilot/kubeconfig"
SA_NS="fleet-copilot"
SA_NAME="fleet-gateway"
TOKEN_DURATION="${FLEET_GATEWAY_TOKEN_DURATION:-8760h}"

_SSH=(ssh -o BatchMode=yes -o ConnectTimeout=20)

usage() {
  echo "Uso: $0 [--host HOST] [--apply|--verify]"
  exit 1
}

ACTION="apply"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) REMOTE_HOST="$2"; shift 2 ;;
    --apply) ACTION="apply"; shift ;;
    --verify) ACTION="verify"; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

verify_rbac() {
  local del get nodes
  del=$("${_SSH[@]}" "$REMOTE_HOST" \
    "kubectl auth can-i delete pods --all-namespaces --as=system:serviceaccount:${SA_NS}:${SA_NAME}" 2>/dev/null || echo "no")
  get=$("${_SSH[@]}" "$REMOTE_HOST" \
    "kubectl auth can-i get pods --all-namespaces --as=system:serviceaccount:${SA_NS}:${SA_NAME}" 2>/dev/null || echo "no")
  nodes=$("${_SSH[@]}" "$REMOTE_HOST" \
    "kubectl auth can-i get nodes --as=system:serviceaccount:${SA_NS}:${SA_NAME}" 2>/dev/null || echo "no")
  echo "delete pods (SA): $del (expected: no)"
  echo "get pods (SA):    $get (expected: yes)"
  echo "get nodes (SA):   $nodes (expected: yes)"
  [[ "$del" == "no" && "$get" == "yes" && "$nodes" == "yes" ]] || return 1
}

verify_kubeconfig_file() {
  local del get
  del=$("${_SSH[@]}" "$REMOTE_HOST" \
    "sudo -u fleet-copilot kubectl auth can-i delete pods --all-namespaces --kubeconfig=$KUBE_PATH" 2>/dev/null || echo "no")
  get=$("${_SSH[@]}" "$REMOTE_HOST" \
    "sudo -u fleet-copilot kubectl auth can-i get pods --all-namespaces --kubeconfig=$KUBE_PATH" 2>/dev/null || echo "no")
  echo "delete pods (kubeconfig): $del (expected: no)"
  echo "get pods (kubeconfig):    $get (expected: yes)"
  [[ "$del" == "no" && "$get" == "yes" ]] || return 1
}

apply_kubeconfig() {
  echo "Applying RBAC on $REMOTE_HOST..."
  scp -q "$MANIFEST" "$REMOTE_HOST:/tmp/fleet-gateway-rbac.yaml"
  "${_SSH[@]}" "$REMOTE_HOST" "kubectl apply -f /tmp/fleet-gateway-rbac.yaml"

  echo "Creating SA token (${TOKEN_DURATION})..."
  local token server ca_b64
  token=$("${_SSH[@]}" "$REMOTE_HOST" \
    "kubectl create token ${SA_NAME} -n ${SA_NS} --duration=${TOKEN_DURATION}")
  server=$("${_SSH[@]}" "$REMOTE_HOST" \
    "kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'")
  ca_b64=$("${_SSH[@]}" "$REMOTE_HOST" \
    "kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}'")

  if [[ -z "$token" || -z "$server" || -z "$ca_b64" ]]; then
    echo "ERRO: não foi possível obter token/server/CA do cluster" >&2
    exit 1
  fi

  local tmp_kcfg
  tmp_kcfg=$(mktemp)
  trap 'rm -f "${tmp_kcfg:-}"' EXIT

  cat >"$tmp_kcfg" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: fleet-ssdnodes
    cluster:
      server: ${server}
      certificate-authority-data: ${ca_b64}
contexts:
  - name: fleet-gateway@fleet-ssdnodes
    context:
      cluster: fleet-ssdnodes
      user: fleet-gateway
      namespace: default
current-context: fleet-gateway@fleet-ssdnodes
users:
  - name: fleet-gateway
    user:
      token: ${token}
EOF

  scp -q "$tmp_kcfg" "$REMOTE_HOST:/tmp/fleet-gateway.kubeconfig"
  rm -f "$tmp_kcfg"
  trap - EXIT
  "${_SSH[@]}" "$REMOTE_HOST" "sudo bash -s" <<REMOTE
set -euo pipefail
mkdir -p /etc/fleet-copilot
install -m 600 -o root -g root /tmp/fleet-gateway.kubeconfig ${KUBE_PATH}
if id fleet-copilot &>/dev/null; then
  chown fleet-copilot:fleet-copilot ${KUBE_PATH}
  chmod 600 ${KUBE_PATH}
fi
grep -q '^FLEET_KUBECONFIG=' /etc/fleet-copilot/gateway.env 2>/dev/null && \
  sed -i 's|^FLEET_KUBECONFIG=.*|FLEET_KUBECONFIG=${KUBE_PATH}|' /etc/fleet-copilot/gateway.env || \
  echo 'FLEET_KUBECONFIG=${KUBE_PATH}' >> /etc/fleet-copilot/gateway.env
REMOTE

  echo "OK: kubeconfig installed at ${KUBE_PATH}"
}

case "$ACTION" in
  apply)
    apply_kubeconfig
    verify_rbac
    if "${_SSH[@]}" "$REMOTE_HOST" "id fleet-copilot" &>/dev/null; then
      verify_kubeconfig_file
    else
      echo "(skip kubeconfig file verify — usuário fleet-copilot ainda não existe; rode install_fleet_ops_gateway.sh)"
    fi
    echo "OK: fleet-gateway view-only RBAC + kubeconfig"
    ;;
  verify)
    verify_rbac
    verify_kubeconfig_file
    echo "OK: view-only verified"
    ;;
esac
