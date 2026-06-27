#!/usr/bin/env bash
# deploy-preflight.sh — Pré-voo obrigatório antes de build/push/deploy no cluster OCI.
#
# Evita regressões pós-reset Nexus (MiniMax): registry vazio, PVC cheio, quota,
# DiskPressure, npm TLS no Alpine/Hetzner, .npmrc ausente.
#
# Uso:
#   source "$REPO_ROOT/oci-k8s-cluster/scripts/lib/deploy-preflight.sh"
#   deploy_preflight_all --namespace default --npmrc apps/back-end/.npmrc
#
# Ou standalone:
#   bash oci-k8s-cluster/scripts/lib/deploy-preflight.sh all --namespace default

set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$_LIB_DIR/../../.." && pwd)}"

DEPLOY_PREFLIGHT_FAIL=0

_pf_ok() { printf '✓ %s\n' "$*"; }
_pf_warn() { printf '⚠ %s\n' "$*" >&2; }
_pf_bad() {
	printf '✗ %s\n' "$*" >&2
	DEPLOY_PREFLIGHT_FAIL=1
}

deploy_preflight_kubectl() {
	if ! command -v kubectl >/dev/null 2>&1; then
		_pf_bad "kubectl não encontrado"
		return
	fi
	if ! kubectl get ns >/dev/null 2>&1; then
		_pf_bad "kubectl sem acesso ao cluster (tunnel/KUBECONFIG?)"
		_pf_warn "Rode: source $REPO_ROOT/oci-k8s-cluster/scripts/setup-dev-deploy.sh"
	fi
}

deploy_preflight_nexus() {
	local min_pvc_free_pct="${NEXUS_MIN_PVC_FREE_PCT:-15}"
	local pw status pvc_pct

	if [[ ! -f "$REPO_ROOT/oci-k8s-cluster/lib/credstore.sh" ]]; then
		_pf_warn "credstore ausente — pulando checagem HTTP do Nexus"
		return
	fi
	# shellcheck source=/dev/null
	source "$REPO_ROOT/oci-k8s-cluster/lib/credstore.sh"
	pw="$(credstore_get_credential nexus-admin 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('password',''))" 2>/dev/null || true)"
	if [[ -z "$pw" ]]; then
		_pf_bad "credencial nexus-admin ausente no credstore"
		return
	fi

	status="$(curl -s -o /dev/null -w '%{http_code}' -u "admin:$pw" "https://nexus.dnor.io/service/rest/v1/status" 2>/dev/null || echo 000)"
	if [[ "$status" == "200" ]]; then
		_pf_ok "Nexus API status 200"
	else
		_pf_bad "Nexus API status $status (esperado 200)"
	fi

	if kubectl get pvc nexus-pvc -n nexus >/dev/null 2>&1; then
		pvc_pct="$(kubectl exec -n nexus deploy/nexus-deployment -- df -P /nexus-data 2>/dev/null | tail -1 | awk '{gsub(/%/,"",$5); print $5}' || echo "")"
		if [[ -n "$pvc_pct" ]]; then
			if [[ "$pvc_pct" -lt $((100 - min_pvc_free_pct)) ]]; then
				_pf_ok "Nexus PVC /nexus-data ${pvc_pct}% usado"
			else
				_pf_bad "Nexus PVC /nexus-data ${pvc_pct}% usado (≥ $((100 - min_pvc_free_pct))% — risco de No space left on device)"
				_pf_warn "Expanda pvc (components/nexus/pvc.yaml) ou trunque logs em /nexus-data/log"
			fi
		fi
	fi
}

deploy_preflight_registry_tunnel() {
	if ss -tlnp 2>/dev/null | grep -q ':31444'; then
		_pf_ok "túnel registry localhost:31444 ativo"
	else
		_pf_warn "túnel localhost:31444 inativo (será aberto no push Hetzner)"
	fi
}

deploy_preflight_npm_registry() {
	local npmrc="${1:-}"
	local registry="${NPM_REGISTRY_URL:-https://nexus.dnor.io/repository/npm-group/}"

	if [[ -z "$npmrc" ]]; then
		return 0
	fi
	if [[ ! -f "$npmrc" ]]; then
		_pf_bad "npmrc ausente: $npmrc (gitignored — copie/crie antes do build)"
		return
	fi
	_pf_ok "npmrc presente: $npmrc"

	export NODE_OPTIONS="${NODE_OPTIONS:---use-openssl-ca}"
	if NODE_OPTIONS="$NODE_OPTIONS" npm ping --registry="$registry" --userconfig=<(grep -v '^cafile=' "$npmrc") >/dev/null 2>&1; then
		_pf_ok "npm ping OK ($registry, NODE_OPTIONS=$NODE_OPTIONS)"
	else
		_pf_bad "npm ping falhou em $registry (use NODE_OPTIONS=--use-openssl-ca; não use cafile no build Alpine)"
	fi
}

deploy_preflight_namespace_quota() {
	local ns="${1:-default}"
	local min_cpu_m="${DEPLOY_MIN_CPU_LIMIT_HEADROOM_M:-200}"
	local used limit avail

	if ! kubectl get resourcequota -n "$ns" >/dev/null 2>&1; then
		_pf_ok "namespace $ns sem ResourceQuota"
		return
	fi

	local quota_line
	quota_line="$(kubectl get resourcequota -n "$ns" -o json 2>/dev/null | python3 -c "
import json,sys,re
data=json.load(sys.stdin)
for q in data.get('items',[]):
    lim=q.get('status',{}).get('hard',{}).get('limits.cpu','')
    used=q.get('status',{}).get('used',{}).get('limits.cpu','')
    if lim:
        print(used, lim)
" 2>/dev/null || true)"

	if [[ -z "$quota_line" ]]; then
		_pf_warn "não foi possível ler quota CPU em $ns"
		return
	fi

	used="$(echo "$quota_line" | awk '{print $1}')"
	limit="$(echo "$quota_line" | awk '{print $2}')"

	avail="$(python3 -c "
import re
def m(v):
    v=str(v)
    if v.endswith('m'): return int(v[:-1])
    return int(float(v)*1000)
u=m('$used'); l=m('$limit')
print(max(0, l-u))
")"

	if [[ "$avail" -ge "$min_cpu_m" ]]; then
		_pf_ok "quota $ns limits.cpu: ${used}/${limit} (livre ~${avail}m)"
	else
		_pf_bad "quota $ns limits.cpu: ${used}/${limit} — só ~${avail}m livres (mín. ${min_cpu_m}m para rollout)"
		_pf_warn "Limpe pods Evicted: kubectl get pods -n $ns --field-selector=status.phase=Failed"
	fi
}

deploy_preflight_disk_pressure() {
	local nodes
	nodes="$(kubectl get nodes -o json 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
for n in data.get('items',[]):
    for c in n.get('status',{}).get('conditions',[]):
        if c.get('type')=='DiskPressure' and c.get('status')=='True':
            print(n['metadata']['name'])
" 2>/dev/null || true)"

	if [[ -z "$nodes" ]]; then
		_pf_ok "nenhum nó com DiskPressure"
	else
		_pf_bad "DiskPressure ativo em: $(echo "$nodes" | tr '\n' ' ')"
		_pf_warn "Rode: bash $REPO_ROOT/scripts/harness/validate_longhorn_headroom_diag.sh"
	fi
}

deploy_preflight_imagepull_backoff() {
	local lines
	lines="$(kubectl get pods -A -o json 2>/dev/null | python3 -c "
import json,sys
data=json.load(sys.stdin)
for p in data.get('items',[]):
    ns=p['metadata']['namespace']
    name=p['metadata']['name']
    for cs in p.get('status',{}).get('containerStatuses',[]) or []:
        w=cs.get('state',{}).get('waiting',{})
        if w.get('reason') in ('ImagePullBackOff','ErrImagePull'):
            img=p['spec']['containers'][0].get('image','')
            print(f'{ns}/{name} -> {img}')
" 2>/dev/null || true)"

	if [[ -z "$lines" ]]; then
		_pf_ok "nenhum pod ImagePullBackOff/ErrImagePull"
	else
		_pf_warn "pods com pull falho (republicar imagem ou regsecret):"
		echo "$lines" | while read -r line; do
			[[ -n "$line" ]] && _pf_warn "  $line"
		done
	fi
}

deploy_cleanup_evicted_pods() {
	local ns="${1:-}"
	local args=(-A --field-selector=status.phase=Failed)
	[[ -n "$ns" ]] && args=(-n "$ns" --field-selector=status.phase=Failed)

	local count
	count="$(kubectl get pods "${args[@]}" -o name 2>/dev/null | grep -c '/pod/' || true)"
	if [[ "$count" -eq 0 ]]; then
		return 0
	fi
	echo "🧹 removendo $count pod(s) Failed/Evicted${ns:+ em $ns}..." >&2
	kubectl delete pods "${args[@]}" --wait=false 2>/dev/null || true
}

deploy_rollout_wait() {
	local deploy="$1" ns="${2:-default}" timeout="${3:-180s}"
	kubectl rollout status "deploy/$deploy" -n "$ns" --timeout="$timeout"
}

deploy_preflight_all() {
	local namespace="default" npmrc="" cleanup_evicted=0

	DEPLOY_PREFLIGHT_FAIL=0

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--namespace | -n) namespace="$2"; shift 2 ;;
		--npmrc) npmrc="$2"; shift 2 ;;
		--cleanup-evicted) cleanup_evicted=1; shift ;;
		*) shift ;;
		esac
	done

	echo "=== deploy preflight (namespace=$namespace) ===" >&2

	deploy_preflight_kubectl
	deploy_preflight_nexus
	deploy_preflight_registry_tunnel
	deploy_preflight_npm_registry "$npmrc"
	deploy_preflight_namespace_quota "$namespace"
	deploy_preflight_disk_pressure
	deploy_preflight_imagepull_backoff

	if [[ "$cleanup_evicted" -eq 1 ]]; then
		deploy_cleanup_evicted_pods "$namespace"
	fi

	if [[ "$DEPLOY_PREFLIGHT_FAIL" -ne 0 ]]; then
		echo "FAIL deploy preflight" >&2
		return 1
	fi
	echo "PASS deploy preflight" >&2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	case "${1:-all}" in
	all)
		shift || true
		deploy_preflight_all "$@"
		;;
	cleanup-evicted)
		shift || true
		ns="${1:-}"
		deploy_cleanup_evicted_pods "$ns"
		;;
	*)
		echo "uso: deploy-preflight.sh all [--namespace NS] [--npmrc PATH] [--cleanup-evicted]" >&2
		exit 2
		;;
	esac
fi
