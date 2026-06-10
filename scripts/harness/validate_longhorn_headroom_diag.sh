#!/usr/bin/env bash
# validate_longhorn_headroom_diag.sh — T-307 harness
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIAG="$REPO_ROOT/oci-k8s-cluster/scripts/observability/longhorn_headroom_diag.sh"

ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; FAIL=1; }

FAIL=0
echo "=== validate_longhorn_headroom_diag (T-307) ==="

if [[ ! -x "$DIAG" ]]; then
	chmod +x "$DIAG"
fi

if ! command -v kubectl >/dev/null 2>&1; then
	bad "kubectl ausente"
	echo "FAIL validate_longhorn_headroom_diag"
	exit 1
fi

if ! kubectl get ns longhorn-system >/dev/null 2>&1; then
	bad "longhorn-system inacessível (tunnel/KUBECONFIG?)"
	echo "FAIL validate_longhorn_headroom_diag"
	exit 1
fi
ok "kubectl + longhorn-system"

out="$(bash "$DIAG" 2>&1)" || {
	bad "longhorn_headroom_diag.sh falhou"
	echo "$out"
	echo "FAIL validate_longhorn_headroom_diag"
	exit 1
}

echo "$out" | grep -q "Longhorn headroom diagnostic" && ok "report header"
echo "$out" | grep -q "k8s-master" && ok "node rows present"
echo "$out" | grep -q "Top volumes" && ok "volume section"

json="$(bash "$DIAG" --json 2>&1)" || {
	bad "--json falhou"
	exit 1
}
echo "$json" | jq -e 'type == "array" and length >= 1' >/dev/null && ok "JSON array output"

if [[ "${FAIL:-0}" -eq 0 ]]; then
	echo "PASS validate_longhorn_headroom_diag"
else
	echo "FAIL validate_longhorn_headroom_diag"
	exit 1
fi
