#!/usr/bin/env bash
# ci-prep.sh — deps path-aware antes do harness (Jenkins / citools)
set -euo pipefail

REPO_ROOT="${CITOOLS_REPO_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}"
cd "$REPO_ROOT"

log() { printf '[ci-prep] %s\n' "$*"; }

if [[ $# -eq 0 ]]; then
	log "nenhum path — skip prep"
	exit 0
fi

need_rust_obs=0 need_bats=0 need_js_backend=0 need_js_react=0 need_js_static=0

for path in "$@"; do
	case "$path" in
	apps/rs-observability-api/*) need_rust_obs=1 ;;
	apps/back-end/*) need_js_backend=1 ;;
	apps/react-static/*) need_js_react=1 ;;
	apps/static/*) need_js_static=1 ;;
	oci-k8s-cluster/testing/* | oci-k8s-cluster/run_tests.sh | oci-k8s-cluster/k8s_ops_menu.sh | oci-k8s-cluster/scripts/* | oci-k8s-cluster/lib/*) need_bats=1 ;;
	esac
done

if [[ "$need_rust_obs" == "1" ]]; then
	log "web-v2 build (rs-observability-api embed)"
	(
		cd apps/rs-observability-api/web-v2
		npm ci --ignore-scripts
		npm run build
	)
fi

if [[ "$need_bats" == "1" ]]; then
	log "BATS setup (oci-k8s-cluster)"
	(
		cd oci-k8s-cluster
		rm -rf ./testing/libs ./testing/bats
		bash ./testing/setup_bats.sh
	)
fi

if [[ "$need_js_backend" == "1" ]]; then
	if getent hosts nexus.dnor.io >/dev/null 2>&1; then
		log "npm ci back-end"
		(
			cd apps/back-end
			npm config set registry https://registry.npmjs.org/
			npm ci --no-audit --no-fund
		)
	else
		log "back-end skip npm — nexus.dnor.io inacessível neste agent"
		export HARNESS_SKIP_JS_BACKEND=1
	fi
fi

if [[ "$need_js_react" == "1" ]]; then
	log "npm ci react-static"
	(
		cd apps/react-static
		npm ci
	)
fi

if [[ "$need_js_static" == "1" ]]; then
	log "npm ci static"
	(
		cd apps/static
		npm ci
	)
fi
