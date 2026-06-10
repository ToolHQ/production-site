#!/usr/bin/env bash
# install_buildkit_guardrails.sh — systemd timer for BuildKit disk policy (T-311)
# Run from dev machine; SSHes to Hetzner builder host.
#
# Usage: ./install_buildkit_guardrails.sh [--dry-run-test]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HETZNER_HOST="${HETZNER_HOST:-hetzner-cax21-helsinki-4vcpu-8gb-ipv4}"
INSTALL_BIN="/usr/local/bin/buildkit_guardrails.sh"
LOG_FILE="/var/log/buildkit-guardrails.log"

DRY_RUN_TEST=0
for arg in "$@"; do
	[[ "$arg" == "--dry-run-test" ]] && DRY_RUN_TEST=1
done

echo "=== install_buildkit_guardrails ($HETZNER_HOST) ==="

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$HETZNER_HOST" "exit" 2>/dev/null; then
	echo "✗ SSH falhou para $HETZNER_HOST" >&2
	exit 1
fi

scp "$SCRIPT_DIR/buildkit_guardrails.sh" "$HETZNER_HOST:/tmp/buildkit_guardrails.sh"
scp "$REPO_ROOT/oci-k8s-cluster/systemd/buildkit-guardrails.service" "$HETZNER_HOST:/tmp/"
scp "$REPO_ROOT/oci-k8s-cluster/systemd/buildkit-guardrails.timer" "$HETZNER_HOST:/tmp/"

ssh "$HETZNER_HOST" "sudo install -m 0755 /tmp/buildkit_guardrails.sh $INSTALL_BIN && \
	sudo mv /tmp/buildkit-guardrails.service /tmp/buildkit-guardrails.timer /etc/systemd/system/ && \
	sudo touch $LOG_FILE && sudo chmod 644 $LOG_FILE && \
	sudo systemctl daemon-reload && \
	sudo systemctl enable buildkit-guardrails.timer && \
	sudo systemctl start buildkit-guardrails.timer"

echo "✓ timer enabled"
ssh "$HETZNER_HOST" "systemctl list-timers buildkit-guardrails.timer --no-pager" || true

if [[ "$DRY_RUN_TEST" == "1" ]]; then
	echo "→ dry-run test"
	ssh "$HETZNER_HOST" "sudo $INSTALL_BIN --dry-run | tail -5"
fi

echo "✓ install_buildkit_guardrails OK"
