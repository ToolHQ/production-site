#!/bin/bash
# E2E test — raw curl against production agent-meter.dnor.io
# No harness, no framework — just HTTP assertions
set -uo pipefail

BASE="https://agent-meter.dnor.io"
OTLP="https://agent-meter.dnor.io"
PASS=0
FAIL=0
TESTS=()

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  ✅ $name"
    ((PASS++))
  else
    echo "  ❌ $name (expected '$expected', got: ${actual:0:200})"
    ((FAIL++))
  fi
  TESTS+=("$name")
}

echo "═══════════════════════════════════════════════"
echo "  agent-meter E2E test suite ($(date))"
echo "  Target: $BASE"
echo "═══════════════════════════════════════════════"
echo ""

# ── 1. Health ────────────────────────────────────────
echo "▸ Health endpoints"
R=$(curl -s "$BASE/health")
check "GET /health returns ok" '"status":"ok"' "$R"

R=$(curl -s "$BASE/health/ready")
check "GET /health/ready returns status" '"status"' "$R"
check "GET /health/ready checks database" '"database"' "$R"
check "GET /health/ready shows buffer" '"ingest_buffer"' "$R"

# ── 2. UI pages (HTML) ───────────────────────────────
echo ""
echo "▸ UI pages"
for page in "/" "/dashboard" "/conversations" "/cost" "/alerts" "/pricing" "/status" "/quickstart" "/docs" "/leaderboard" "/vs"; do
  CODE=$(curl -s -o /dev/null -L -w "%{http_code}" "$BASE$page")
  check "GET $page → 200" "200" "$CODE"
done

# ── 3. API endpoints ─────────────────────────────────
echo ""
echo "▸ API endpoints"
R=$(curl -s "$BASE/api/billing/plans")
check "GET /api/billing/plans returns JSON array" "[" "$R"

R=$(curl -s "$BASE/api/conversations?limit=3")
check "GET /api/conversations returns data" "[" "$R"

R=$(curl -s "$BASE/api/search?q=test&limit=5")
check "GET /api/search?q=test returns array" "[" "$R"

R=$(curl -s "$BASE/reports/top-tools?from=2026-01-01")
check "GET /reports/top-tools returns JSON" "[" "$R"

R=$(curl -s "$BASE/reports/top-mcp-servers?from=2026-01-01")
check "GET /reports/top-mcp-servers returns JSON" "[" "$R"

R=$(curl -s "$BASE/reports/models")
check "GET /reports/models returns array" "[" "$R"

R=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/api/export/events.csv?from=2026-06-01")
check "GET /api/export/events.csv → 200" "200" "$R"

R=$(curl -s "$BASE/api/stats/public")
check "GET /api/stats/public returns total_events" "total_events" "$R"
check "GET /api/stats/public returns events_24h" "events_24h" "$R"

# ── 4. SEO assets ────────────────────────────────────
echo ""
echo "▸ SEO assets"
R=$(curl -s "$BASE/robots.txt")
check "GET /robots.txt has sitemap ref" "Sitemap:" "$R"

R=$(curl -s "$BASE/sitemap.xml")
check "GET /sitemap.xml is valid XML" "<urlset" "$R"

# ── 4. OTLP ingest (fire actual span) ────────────────
echo ""
echo "▸ OTLP ingest"
TRACE_ID=$(printf '%032x' $RANDOM$RANDOM$RANDOM$RANDOM)
SPAN_ID=$(printf '%016x' $RANDOM$RANDOM)
NOW_NS=$(date +%s)000000000
END_NS=$((NOW_NS + 150000000))

OTLP_BODY=$(cat <<EOF
{
  "resourceSpans": [{
    "resource": {"attributes": [
      {"key": "service.name", "value": {"stringValue": "e2e-test-suite"}}
    ]},
    "scopeSpans": [{
      "spans": [{
        "traceId": "$TRACE_ID",
        "spanId": "$SPAN_ID",
        "name": "execute_tool e2e_health_check",
        "kind": 1,
        "startTimeUnixNano": "$NOW_NS",
        "endTimeUnixNano": "$END_NS",
        "status": {"code": 1},
        "attributes": [
          {"key": "tool.name", "value": {"stringValue": "e2e_health_check"}},
          {"key": "gen_ai.request.model", "value": {"stringValue": "gpt-4o-e2e"}}
        ]
      }]
    }]
  }]
}
EOF
)

R=$(curl -s -X POST "$OTLP/v1/traces" \
  -H "Content-Type: application/json" \
  -d "$OTLP_BODY")
check "POST /v1/traces returns JSON response" "[" "$R"
check "POST /v1/traces buffered or inserted" "tool_name" "$R"

# ── 5. Rate limiter (should NOT trigger on first request) ──
echo ""
echo "▸ Rate limiter"
CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$OTLP/v1/traces" \
  -H "Content-Type: application/json" \
  -d "$OTLP_BODY")
check "Second ingest request not rate-limited" "200" "$CODE"

# ── 6. Static assets ─────────────────────────────────
echo ""
echo "▸ Static assets"
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/_static/app.js")
check "GET /_static/app.js → 200" "200" "$CODE"

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/_static/app.css")
check "GET /_static/app.css → 200" "200" "$CODE"

CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/_static/tokens.css")
check "GET /_static/tokens.css → 200" "200" "$CODE"

# ── 7. 404 page ──────────────────────────────────────
echo ""
echo "▸ Error handling"
CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/nonexistent-page-xyz")
check "GET /nonexistent → 404" "404" "$CODE"

# ── Summary ───────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed ($(( PASS + FAIL )) total)"
echo "═══════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
