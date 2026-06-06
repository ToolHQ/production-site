#!/usr/bin/env bash
# deploy-run.sh — worker wrapper + deploy.sh (T-347)
# Uso: CITOOLS_DEPLOY_APP=py-back-end CITOOLS_DEPLOY_TARGET=oci CITOOLS_BUILD_WORKER=hetzner ./deploy-run.sh ./apps/py-back-end/deploy.sh
set -euo pipefail

REPO_ROOT="${CITOOLS_REPO_ROOT:-$(cd "$(dirname "$0")/../../.." && pwd)}"
SCRIPT="${1:?script deploy.sh}"
WORKER="${CITOOLS_BUILD_WORKER:-hetzner}"
TARGET="${CITOOLS_DEPLOY_TARGET:-oci}"
APP="${CITOOLS_DEPLOY_APP:-unknown}"

cd "$REPO_ROOT"
export REPO_ROOT

echo "[deploy-run] app=$APP worker=$WORKER target=$TARGET script=$SCRIPT" >&2

# shellcheck source=/dev/null
source "$REPO_ROOT/tools/citools/scripts/deploy-target-env.sh"

case "$WORKER" in
hetzner)
	if ! command -v docker >/dev/null 2>&1; then
		echo "❌ docker ausente — worker hetzner exige docker+buildx no executor" >&2
		echo "   Rode localmente ou configure agent Jenkins com docker (T-347)" >&2
		exit 1
	fi
	SETUP_HETZ="$REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh"
	if [[ -x "$SETUP_HETZ" ]] && ! "$SETUP_HETZ" --silent 2>/dev/null; then
		echo "❌ hetzner-builder indisponível — rode: $SETUP_HETZ" >&2
		exit 1
	fi
	export USE_HETZNER=true
	;;
ssdnodes-agent)
	echo "⚠️  ssdnodes-agent: build x86 no agent (sem buildx remoto) — fase 2" >&2
	;;
local)
	echo "[deploy-run] worker=local (sem prep extra)" >&2
	;;
*)
	echo "❌ worker desconhecido: $WORKER" >&2
	exit 2
	;;
esac

exec bash "$SCRIPT"
