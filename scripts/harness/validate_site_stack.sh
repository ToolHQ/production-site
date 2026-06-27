#!/usr/bin/env bash
# validate_site_stack.sh — Harness pós-deploy do stack dnor.io (nginx + back-end + registry).
#
#   bash scripts/harness/validate_site_stack.sh
#   bash scripts/harness/validate_site_stack.sh --deploy-back-end  # preflight + deploy + validate

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DEPLOY_BACK_END=0
DEPLOY_NGINX=0
TIMEOUT="180s"

while [[ $# -gt 0 ]]; do
	case "$1" in
	--deploy-back-end) DEPLOY_BACK_END=1; shift ;;
	--deploy-nginx) DEPLOY_NGINX=1; shift ;;
	--timeout) TIMEOUT="$2"; shift 2 ;;
	-h | --help)
		grep '^#' "$0" | head -8
		exit 0
		;;
	*) echo "argumento desconhecido: $1" >&2; exit 2 ;;
	esac
done

export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml}"
export REPO_ROOT

FAIL=0
ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; FAIL=1; }

if [[ "$DEPLOY_BACK_END" -eq 1 || "$DEPLOY_NGINX" -eq 1 ]]; then
	# shellcheck source=/dev/null
	source "$REPO_ROOT/oci-k8s-cluster/scripts/setup-dev-deploy.sh" >/dev/null 2>&1 || true
	bash "$SCRIPT_DIR/validate_deploy_readiness.sh" --namespace default --cleanup-evicted \
		${DEPLOY_BACK_END:+--npmrc "$REPO_ROOT/apps/back-end/.npmrc"} --hetzner
fi

if [[ "$DEPLOY_BACK_END" -eq 1 ]]; then
	echo "=== deploy my-site-back-end ==="
	(cd "$REPO_ROOT/apps/back-end" && ./deploy.sh)
fi

if [[ "$DEPLOY_NGINX" -eq 1 ]]; then
	echo "=== publish my-site-nginx ==="
	(cd "$REPO_ROOT/apps/nginx" && ./publish.sh)
fi

echo "=== validate_site_stack ==="

for dep in my-site-nginx-deployment my-site-back-end-deployment; do
	if kubectl rollout status "deploy/$dep" -n default --timeout="$TIMEOUT" >/dev/null 2>&1; then
		ok "rollout $dep"
	else
		bad "rollout $dep (timeout ou falha)"
	fi
done

nginx_pod="$(kubectl get pods -n default -l app=my-site-nginx -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo Unknown)"
be_pod="$(kubectl get pods -n default -l app=my-site-back-end -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo Unknown)"

[[ "$nginx_pod" == "Running" ]] && ok "pod nginx $nginx_pod" || bad "pod nginx $nginx_pod"
[[ "$be_pod" == "Running" ]] && ok "pod back-end $be_pod" || bad "pod back-end $be_pod"

api_code="$(curl -s -o /dev/null -w '%{http_code}' https://dnor.io/api/health 2>/dev/null || echo 000)"
[[ "$api_code" == "200" ]] && ok "https://dnor.io/api/health → $api_code" || bad "api/health → $api_code"

pull_fail="$(kubectl get pods -A -o json 2>/dev/null | python3 -c "
import json,sys
n=0
for p in json.load(sys.stdin).get('items',[]):
    for cs in p.get('status',{}).get('containerStatuses',[]) or []:
        if cs.get('state',{}).get('waiting',{}).get('reason') in ('ImagePullBackOff','ErrImagePull'):
            n+=1
print(n)
" 2>/dev/null || echo "?")"

if [[ "$pull_fail" == "0" ]]; then
	ok "ImagePullBackOff cluster-wide: 0"
else
	bad "ImagePullBackOff cluster-wide: $pull_fail pod(s)"
fi

echo ""
if [[ "$FAIL" -eq 0 ]]; then
	echo "PASS validate_site_stack"
	exit 0
fi
echo "FAIL validate_site_stack"
exit 1
