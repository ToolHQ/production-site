#!/usr/bin/env bash
# deploy-target-env.sh — KUBECONFIG por target (T-347)
set -euo pipefail

REPO_ROOT="${CITOOLS_REPO_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TARGET="${CITOOLS_DEPLOY_TARGET:-oci}"

case "$TARGET" in
oci)
	# shellcheck source=/dev/null
	source "$REPO_ROOT/oci-k8s-cluster/scripts/setup-dev-deploy.sh" 2>/dev/null || true
	export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
	;;
ssdnodes)
	export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/ssdnodes.yaml}"
	;;
*)
	echo "❌ target desconhecido: $TARGET (oci|ssdnodes)" >&2
	exit 2
	;;
esac

echo "[deploy-target] KUBECONFIG=$KUBECONFIG target=$TARGET" >&2
