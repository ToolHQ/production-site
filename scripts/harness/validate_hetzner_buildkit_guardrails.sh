#!/usr/bin/env bash
# validate_hetzner_buildkit_guardrails.sh — T-311 harness
set -euo pipefail

HETZNER_HOST="${HETZNER_HOST:-hetzner-cax21-helsinki-4vcpu-8gb-ipv4}"
MAX_USED_PCT="${MAX_USED_PCT:-80}"

ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; FAIL=1; }

FAIL=0
echo "=== validate_hetzner_buildkit_guardrails (T-311) ==="

if ! ssh -o ConnectTimeout=15 -o BatchMode=yes "$HETZNER_HOST" "exit" 2>/dev/null; then
	bad "SSH falhou ($HETZNER_HOST)"
	echo "FAIL validate_hetzner_buildkit_guardrails"
	exit 1
fi
ok "SSH ($HETZNER_HOST)"

read -r used_pct _ <<<"$(ssh "$HETZNER_HOST" "df -P / | tail -1 | awk '{gsub(/%/,\"\",\$5); print \$5}'")"
if [[ "${used_pct:-100}" -lt "$MAX_USED_PCT" ]]; then
	ok "rootfs ${used_pct}% (< ${MAX_USED_PCT}%)"
else
	bad "rootfs ${used_pct}% — acima do threshold ${MAX_USED_PCT}%"
fi

if ssh "$HETZNER_HOST" "test -x /usr/local/bin/buildkit_guardrails.sh" 2>/dev/null; then
	ok "buildkit_guardrails.sh instalado"
else
	bad "script ausente em /usr/local/bin/buildkit_guardrails.sh"
fi

timer_state="$(ssh "$HETZNER_HOST" "systemctl is-enabled buildkit-guardrails.timer 2>/dev/null || echo disabled")"
if [[ "$timer_state" == "enabled" ]]; then
	ok "buildkit-guardrails.timer enabled"
else
	bad "timer não enabled ($timer_state)"
fi

if ssh "$HETZNER_HOST" "test -s /var/log/buildkit-guardrails.log" 2>/dev/null; then
	ok "log /var/log/buildkit-guardrails.log presente"
else
	bad "log ausente ou vazio"
fi

if docker buildx inspect hetzner-builder >/dev/null 2>&1; then
	ok "buildx hetzner-builder registrado localmente"
else
	bad "buildx hetzner-builder ausente localmente"
fi

if [[ "${FAIL:-0}" -eq 0 ]]; then
	echo "PASS validate_hetzner_buildkit_guardrails"
else
	echo "FAIL validate_hetzner_buildkit_guardrails"
	exit 1
fi
