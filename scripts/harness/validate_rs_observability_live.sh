#!/usr/bin/env bash
set -euo pipefail

DO_DEPLOY=false
if [[ "${1:-}" == "--deploy" ]]; then
  DO_DEPLOY=true
fi

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_DIR="$ROOT_DIR/apps/rs-observability-api"

source "$ROOT_DIR/oci-k8s-cluster/scripts/setup-dev-deploy.sh"
export KUBECONFIG="${KUBECONFIG:-$ROOT_DIR/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
export CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-$ROOT_DIR/tmp/ca-bundles/system-plus-dnor-ca.pem}"

if [[ "$DO_DEPLOY" == "true" ]]; then
  echo "[harness] Deploying rs-observability-api..."
  (cd "$APP_DIR" && ./deploy.sh)
fi

echo "[harness] Waiting rollout..."
kubectl rollout status deploy/rs-observability-api-deployment -n default --timeout=180s

echo "[harness] Current deployment image:"
kubectl get deploy rs-observability-api-deployment -n default -o jsonpath='{.spec.template.spec.containers[0].image}'
echo

echo "[harness] Running pod(s):"
kubectl get pods -n default -l app=rs-observability-api \
  -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,IMAGE:.spec.containers[0].image --no-headers

tmp_payload="$(mktemp)"
trap 'rm -f "$tmp_payload"' EXIT
curl -fsS https://reports.dnor.io/api/live/overview -o "$tmp_payload"

python3 - "$tmp_payload" <<'PY'
import json
import sys

payload_path = sys.argv[1]
with open(payload_path, "r", encoding="utf-8") as f:
    p = json.load(f)

nodes = p.get("nodes", [])
print("[harness] API status:", "available=" + str(p.get("available")), "nodes=" + str(len(nodes)))

required = all(all(k in n for k in ("ip", "architecture", "operating_system")) for n in nodes)
print("[harness] required_fields_all_nodes=", required)

external = [
    n for n in nodes
    if n.get("cluster") in ("HETZNER", "SSD-NODES") or n.get("ip") in ("37.27.85.100", "104.225.218.78")
]

if not external:
    print("[harness] external_nodes=0")
else:
    print("[harness] external_nodes=")
    for n in external:
        print(
            "  -",
            f"{n.get('name')} | cluster={n.get('cluster')} role={n.get('role')} ip={n.get('ip')} arch={n.get('architecture')} os={n.get('operating_system')} ready={n.get('ready')}"
        )
PY

echo "[harness] Live validation completed."
