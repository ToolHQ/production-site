#!/usr/bin/env bash
# run_fleet_copilot_e2e.sh — Playwright smoke (T-328)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/e2e"
export REPORTS_URL="${REPORTS_URL:-https://reports.dnor.io}"
if [[ ! -d node_modules ]]; then
  npm ci --ignore-scripts 2>/dev/null || npm install --ignore-scripts
fi
npx playwright install chromium --with-deps 2>/dev/null || npx playwright install chromium
npm test
