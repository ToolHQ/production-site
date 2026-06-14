#!/usr/bin/env bash
# validate_t340_visual.sh — T-340 visual/UX checks via CLI (bundle + API)
# Browser screenshots: agente via chromeDevtools MCP (ver checklist)
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORTS_URL="${REPORTS_URL:-https://reports.dnor.io}"

pass=0
fail=0

ok()  { echo "[  ok ] $*"; pass=$((pass + 1)); }
bad() { echo "[FAIL] $*"; fail=$((fail + 1)); }

echo "=== T-340 visual validation (CLI) ==="

if curl -fsS --max-time 12 "$REPORTS_URL/health" | grep -q '"status":"ok"'; then
  ok "reports health"
else
  bad "reports health"
fi

if curl -fsS --max-time 15 "$REPORTS_URL/api/live/overview" | grep -q '"available":true'; then
  ok "live overview available"
else
  bad "live overview"
fi

html=$(curl -fsS --max-time 15 "$REPORTS_URL/" 2>/dev/null || true)
if [[ -z "$html" ]]; then
  bad "fetch index.html"
else
  js_asset=$(echo "$html" | grep -oE '/assets/app\.js[^" ]*' | head -1)
  css_asset=$(echo "$html" | grep -oE '/assets/app\.css[^" ]*' | head -1)
  if [[ -n "$js_asset" && -n "$css_asset" ]]; then
    ok "asset paths resolved"
    js_body=$(curl -fsS --max-time 20 "$REPORTS_URL$js_asset")
    css_body=$(curl -fsS --max-time 20 "$REPORTS_URL$css_asset")

    for needle in dnor-overview-nav dnor-platform-fold dnor-catalog-cta storage-row--pressure; do
      if echo "$css_body" | grep -q "$needle"; then
        ok "CSS contains $needle"
      else
        bad "CSS missing $needle"
      fi
    done
    if echo "$js_body" | grep -q 'fleet-cluster-header'; then
      ok "JS contains fleet-cluster-header"
    else
      bad "JS missing fleet-cluster-header"
    fi

    for forbidden in 'This block should explain' 'IMMEDIATE ACTION' 'Waiting for node data' 'Next action'; do
      if echo "$js_body" | grep -q "$forbidden"; then
        bad "bundle still has EN placeholder: $forbidden"
      else
        ok "no '$forbidden' in bundle"
      fi
    done

    if echo "$js_body" | grep -q 'Próxima ação'; then
      ok "PT-BR próxima ação in bundle"
    else
      bad "missing Próxima ação"
    fi

    if echo "$css_body" | grep -q ':root\.dark'; then
      ok "dark theme rules present in CSS"
    else
      bad "missing :root.dark rules"
    fi
  else
    bad "could not parse app.js/app.css from index"
  fi
fi

if [[ -f "$ROOT_DIR/oci-k8s-cluster/kubeconfig_tunnel.yaml" ]]; then
  export KUBECONFIG="$ROOT_DIR/oci-k8s-cluster/kubeconfig_tunnel.yaml"
  if ! ss -tlnp 2>/dev/null | grep -q ':6445'; then
    ssh -o BatchMode=yes -o ConnectTimeout=10 -L 6445:localhost:6443 oci-k8s-master -N -f 2>/dev/null || true
    sleep 1
  fi
  img=$(kubectl get deployment rs-observability-api-deployment -n default \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
  if [[ -n "$img" ]]; then
    ok "cluster image $img"
  else
    bad "kubectl image"
  fi
fi

echo ""
echo "=== Result: $pass passed, $fail failed ==="
echo "Checklist: tasks/2026/Q2/T-340-visual-validation-checklist.md"
echo "MCP: 7 views + dark mode — chromeDevtools (screenshots)"
[[ "$fail" -eq 0 ]]
