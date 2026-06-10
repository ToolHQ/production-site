#!/usr/bin/env bash
# check-hetzner-builder.sh — Diagnóstico rápido do builder Hetzner (T-222).
set -euo pipefail

HETZNER_HOST="${HETZNER_HOST:-hetzner-cax21-helsinki-4vcpu-8gb-ipv4}"
BUILDER_NAME="${BUILDER_NAME:-hetzner-builder}"
SSH_TIMEOUT="${HETZNER_SSH_TIMEOUT:-15}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
bad()  { echo -e "${RED}✗${NC} $*"; }

echo "=== Hetzner builder check ($HETZNER_HOST) ==="

if ssh -o ConnectTimeout="$SSH_TIMEOUT" -o BatchMode=yes "$HETZNER_HOST" "exit" 2>/dev/null; then
	ok "SSH ($HETZNER_HOST)"
else
	bad "SSH falhou — verifique ~/.ssh/config (Host $HETZNER_HOST) e chave ~/.ssh/id_rsa"
	exit 1
fi

docker_state="$(ssh -o ConnectTimeout="$SSH_TIMEOUT" "$HETZNER_HOST" "systemctl is-active docker" 2>/dev/null || echo inactive)"
if [[ "$docker_state" == "active" ]]; then
	ok "Docker daemon na VM"
else
	bad "Docker inativo na VM ($docker_state)"
	exit 1
fi

ssh -o ConnectTimeout="$SSH_TIMEOUT" "$HETZNER_HOST" 'df -h / | tail -1; docker ps -a --filter name=buildx_buildkit --format "{{.Names}} {{.Status}}" 2>/dev/null | head -3' || true

timer_state="$(ssh -o ConnectTimeout="$SSH_TIMEOUT" "$HETZNER_HOST" "systemctl is-enabled buildkit-guardrails.timer 2>/dev/null || echo disabled")"
if [[ "$timer_state" == "enabled" ]]; then
	ok "buildkit-guardrails.timer"
else
	warn "buildkit-guardrails.timer ausente ($timer_state) — rode: $REPO_ROOT/oci-k8s-cluster/scripts/hetzner/install_buildkit_guardrails.sh"
fi

if docker context inspect hetzner >/dev/null 2>&1; then
	ok "Docker context local: hetzner"
else
	warn "Context hetzner ausente — rode: $REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh"
fi

if docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
	status="$(docker buildx inspect "$BUILDER_NAME" 2>/dev/null | grep -o 'Status:.*' | head -1 || true)"
	if echo "$status" | grep -qi running; then
		ok "buildx $BUILDER_NAME ($status)"
	else
		warn "buildx $BUILDER_NAME existe mas não está running — bootstrap:"
		echo "  docker buildx inspect $BUILDER_NAME --bootstrap"
		exit 1
	fi
else
	bad "buildx $BUILDER_NAME não registrado localmente"
	echo "  Rode: $REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh"
	exit 1
fi

if [[ -f "$REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh" ]]; then
	if "$REPO_ROOT/oci-k8s-cluster/scripts/setup-hetzner-builder.sh" --silent; then
		ok "setup-hetzner-builder.sh --silent (pronto para deploy)"
	else
		bad "setup-hetzner-builder.sh --silent falhou (ver mensagens acima)"
		exit 1
	fi
fi

echo ""
echo "Builder OK — use ./deploy.sh (Hetzner-first via deploy-buildx.sh)."
