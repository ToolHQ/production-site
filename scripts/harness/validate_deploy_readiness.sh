#!/usr/bin/env bash
# validate_deploy_readiness.sh — Harness pré-deploy (cluster + Nexus + quota + npm).
#
# Rode ANTES de qualquer ./deploy.sh em sessão de recovery ou entrega crítica:
#   source oci-k8s-cluster/scripts/setup-dev-deploy.sh
#   export KUBECONFIG=oci-k8s-cluster/kubeconfig_tunnel.yaml
#   bash scripts/harness/validate_deploy_readiness.sh
#
# Opções:
#   --namespace default   namespace alvo do rollout
#   --npmrc PATH          valida npm ping (apps Node com @dnorio)
#   --cleanup-evicted     remove pods Failed/Evicted no namespace
#   --hetzner             inclui validate_hetzner_buildkit_guardrails.sh
#   --longhorn            inclui validate_longhorn_headroom_diag.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

NS="default"
NPMRC=""
CLEANUP=0
CHECK_HETZNER=0
CHECK_LONGHORN=0

while [[ $# -gt 0 ]]; do
	case "$1" in
	--namespace | -n) NS="$2"; shift 2 ;;
	--npmrc) NPMRC="$2"; shift 2 ;;
	--cleanup-evicted) CLEANUP=1; shift ;;
	--hetzner) CHECK_HETZNER=1; shift ;;
	--longhorn) CHECK_LONGHORN=1; shift ;;
	-h | --help)
		head -15 "$0" | tail -n +2
		exit 0
		;;
	*) echo "argumento desconhecido: $1" >&2; exit 2 ;;
	esac
done

export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
export REPO_ROOT

FAIL=0

run_gate() {
	local name="$1"
	shift
	echo ""
	echo "=== $name ==="
	if "$@"; then
		echo "PASS $name"
	else
		echo "FAIL $name"
		FAIL=1
	fi
}

run_gate "deploy-preflight" \
	bash "$REPO_ROOT/oci-k8s-cluster/scripts/lib/deploy-preflight.sh" all \
	--namespace "$NS" \
	${NPMRC:+--npmrc "$NPMRC"} \
	$([[ "$CLEANUP" -eq 1 ]] && echo --cleanup-evicted)

if [[ "$CHECK_HETZNER" -eq 1 ]]; then
	run_gate "hetzner-buildkit-guardrails" \
		bash "$SCRIPT_DIR/validate_hetzner_buildkit_guardrails.sh"
fi

if [[ "$CHECK_LONGHORN" -eq 1 ]]; then
	run_gate "longhorn-headroom" \
		bash "$SCRIPT_DIR/validate_longhorn_headroom_diag.sh"
fi

echo ""
if [[ "$FAIL" -eq 0 ]]; then
	echo "PASS validate_deploy_readiness"
	exit 0
fi
echo "FAIL validate_deploy_readiness"
exit 1
