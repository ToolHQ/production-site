#!/usr/bin/env bash
# validate_citools_deploy_plan.sh — T-346 smoke (list + plan all apps, dry-run)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

CITOOLS="${CITOOLS_BIN:-$REPO_ROOT/tools/citools/target/release/citools}"

if [[ ! -x "$CITOOLS" ]]; then
	echo "Building citools..."
	( cd "$REPO_ROOT/tools/citools" && cargo build --release )
fi

ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; exit 1; }

echo "=== validate_citools_deploy_plan (T-346) ==="

"$CITOOLS" deploy list >/dev/null || bad "deploy list"
ok "deploy list"

for app in py-back-end back-end rs-axum-back-end rs-observability-api agent-meter ai-radar gta-vi tor; do
	"$CITOOLS" deploy plan --app "$app" | jq -e ".app == \"$app\"" >/dev/null \
		|| bad "deploy plan --app $app"
done
ok "deploy plan (8 apps)"

"$CITOOLS" deploy run --app py-back-end --dry-run >/dev/null 2>&1 || bad "deploy run --dry-run"
ok "deploy run --dry-run"

"$CITOOLS" deploy run --changed --dry-run >/dev/null 2>&1 || bad "deploy run --changed --dry-run"
ok "deploy run --changed --dry-run"

echo "PASS validate_citools_deploy_plan"
