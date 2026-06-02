#!/usr/bin/env bash
# setup_fleet_copilot_secret.sh — Cria Secret K8s fleet-copilot-creds (T-322).
set -euo pipefail

GATEWAY_TOKEN="${FLEET_COPILOT_GATEWAY_TOKEN:-}"
if [[ -z "$GATEWAY_TOKEN" ]]; then
  GATEWAY_TOKEN=$(ssh ssdnodes-6a12f10c9ef11 "sudo grep FLEET_GATEWAY_TOKEN /etc/fleet-copilot/gateway.env | cut -d= -f2")
fi

LOGIN_KEY="${FLEET_COPILOT_LOGIN_KEY:-$(openssl rand -hex 8)}"
SESSION_SECRET="${FLEET_COPILOT_SESSION_SECRET:-$(openssl rand -hex 32)}"
GATEWAY_URL="${FLEET_COPILOT_GATEWAY_URL:-http://104.225.218.78:18443}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml}"

kubectl create secret generic fleet-copilot-creds \
  --from-literal=FLEET_COPILOT_ENABLED=true \
  --from-literal=FLEET_COPILOT_LOGIN_KEY="$LOGIN_KEY" \
  --from-literal=FLEET_COPILOT_SESSION_SECRET="$SESSION_SECRET" \
  --from-literal=FLEET_COPILOT_GATEWAY_URL="$GATEWAY_URL" \
  --from-literal=FLEET_COPILOT_GATEWAY_TOKEN="$GATEWAY_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Fleet Copilot secret applied."
echo "Login URL: https://reports.dnor.io/fleet-copilot?key=${LOGIN_KEY}"
echo "(cookie 8h — guarde a login key em local seguro)"
