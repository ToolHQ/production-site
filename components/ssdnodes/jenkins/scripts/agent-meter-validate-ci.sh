#!/usr/bin/env bash
# agent-meter-validate-ci.sh — OTLP harness (substitui agent-meter-validation.yml GHA)
set -euo pipefail

REPO_ROOT="${CITOOLS_REPO_ROOT:-$(git rev-parse --show-toplevel)}"
cd "$REPO_ROOT/apps/agent-meter"

echo "[agent-meter-validate] cargo test otlp_regression + validate scripts"

chmod +x scripts/validate_*.sh 2>/dev/null || true
if [[ -x scripts/validate_all_agents.sh ]]; then
  bash scripts/validate_all_agents.sh
else
  cargo test --package agent-meter-collector --test otlp_regression
fi

echo "✓ agent-meter OTLP validation OK"
