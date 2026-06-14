#!/usr/bin/env bash
# validate_fleet_copilot.sh — Live validation harness (T-315 MVP)
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
GATEWAY_URL="${FLEET_GATEWAY_URL:-http://104.225.218.78:18443}"
REPORTS_URL="${REPORTS_URL:-https://reports.dnor.io}"
LOGIN_KEY="${FLEET_COPILOT_LOGIN_KEY:-}"
COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

pass=0
fail=0

ok()   { echo "[  ok ] $*"; pass=$((pass + 1)); }
bad()  { echo "[FAIL] $*"; fail=$((fail + 1)); }

echo "=== Fleet Copilot live validation ==="

if curl -fsS --max-time 10 "$GATEWAY_URL/health" | grep -q '"status":"ok"'; then
  ok "gateway health $GATEWAY_URL/health"
else
  bad "gateway health $GATEWAY_URL/health"
fi

if ssh -o ConnectTimeout=10 -o BatchMode=yes ssdnodes-6a12f10c9ef11 \
  "curl -fsS --max-time 5 http://127.0.0.1:11434/api/tags >/dev/null && \
   systemctl is-active fleet-ops-gateway >/dev/null && \
   sudo ufw status | grep -q '11434.*DENY'"; then
  ok "SSDNodes ollama localhost + gateway + ufw deny 11434"
else
  bad "SSDNodes stack check"
fi

if curl -fsS --max-time 15 "$REPORTS_URL/health" | grep -q rs-observability-api; then
  ok "reports health"
else
  bad "reports health"
fi

if [[ -z "$LOGIN_KEY" ]]; then
  if [[ -f "$ROOT_DIR/oci-k8s-cluster/kubeconfig_tunnel.yaml" ]]; then
    export KUBECONFIG="$ROOT_DIR/oci-k8s-cluster/kubeconfig_tunnel.yaml"
    if ! ss -tlnp 2>/dev/null | grep -q ':6445'; then
      ssh -o BatchMode=yes -o ConnectTimeout=10 -L 6445:localhost:6443 oci-k8s-master -N -f 2>/dev/null || true
      sleep 1
    fi
    LOGIN_KEY=$(kubectl get secret fleet-copilot-creds -n default -o jsonpath='{.data.FLEET_COPILOT_LOGIN_KEY}' 2>/dev/null | base64 -d 2>/dev/null || true)
  fi
fi

if [[ -z "$LOGIN_KEY" ]]; then
  bad "login key missing (set FLEET_COPILOT_LOGIN_KEY or kubectl secret)"
else
  code=$(curl -sS -c "$COOKIE_JAR" -o /dev/null -w '%{http_code}' "$REPORTS_URL/fleet-copilot?key=$LOGIN_KEY")
  if [[ "$code" == "302" ]]; then
    ok "login redirect ($code)"
  else
    bad "login redirect expected 302 got $code"
  fi

  session=$(curl -sS -b "$COOKIE_JAR" "$REPORTS_URL/api/fleet/copilot/session")
  if echo "$session" | grep -q '"authenticated":true'; then
    ok "session authenticated"
  else
    bad "session not authenticated: $session"
  fi

  sse_sample=$(curl -sS -N -b "$COOKIE_JAR" --max-time 45 \
    -X POST "$REPORTS_URL/api/fleet/chat/stream" \
    -H 'Content-Type: application/json' \
    -H 'Accept: text/event-stream' \
    -d '{"message":"ping","preset":"ssdnodes-health"}' 2>&1 || true)

  if echo "$sse_sample" | grep -q 'event: phase'; then
    ok "SSE stream phase events"
  else
    bad "SSE stream missing phase events"
    echo "$sse_sample" | tail -10
  fi

  # T-332 — meta question should list fleet hosts (not only disk output)
  meta_reply=$(curl -sS -b "$COOKIE_JAR" --max-time 30 \
    -X POST "$REPORTS_URL/api/fleet/chat" \
    -H 'Content-Type: application/json' \
    -d '{"message":"Quais hosts você analisa? Liste clusters e nomes.","preset":"ssdnodes-health"}' 2>/dev/null || true)
  meta_lower=$(echo "$meta_reply" | tr '[:upper:]' '[:lower:]')
  meta_hits=0
  for needle in hetzner ssdnodes oci aws 6a12f10c9ef11; do
    if echo "$meta_lower" | grep -q "$needle"; then
      meta_hits=$((meta_hits + 1))
    fi
  done
  if echo "$meta_reply" | grep -qE 'fleet-manifest|fleet-metrics|fleet-structured'; then
    ok "T-332 meta reply via fleet fast path"
  elif [[ "$meta_hits" -ge 3 ]] && ! echo "$meta_lower" | grep -qE 'filesystem|/dev/|avail'; then
    ok "T-332 meta hosts reply mentions fleet ($meta_hits markers)"
  elif [[ "$meta_hits" -ge 2 ]]; then
    ok "T-332 meta hosts reply partial ($meta_hits markers)"
  else
    bad "T-332 meta hosts reply weak (hits=$meta_hits): $(echo "$meta_reply" | head -c 200)"
  fi

  oci_reply=$(curl -sS -b "$COOKIE_JAR" --max-time 30 \
    -X POST "$REPORTS_URL/api/fleet/chat" \
    -H 'Content-Type: application/json' \
    -d '{"message":"@k8s-node-1 Como está a memória?","preset":"ssdnodes-health"}' 2>/dev/null || true)
  if echo "$oci_reply" | grep -qE 'fleet-metrics|k8s-node-1|mem'; then
    ok "T-333 OCI node fast path (@k8s-node-1)"
  else
    bad "T-333 OCI node reply weak: $(echo "$oci_reply" | head -c 180)"
  fi

  cmp_reply=$(curl -sS -b "$COOKIE_JAR" --max-time 30 \
    -X POST "$REPORTS_URL/api/fleet/chat" \
    -H 'Content-Type: application/json' \
    -d '{"message":"Compare disco SSDNodes vs hetzner builder","preset":"ssdnodes-health"}' 2>/dev/null || true)
  if echo "$cmp_reply" | grep -qiE 'comparativo|fleet-metrics|hetzner|ssdnodes'; then
    ok "T-333 compare fast path"
  else
    bad "T-333 compare reply weak: $(echo "$cmp_reply" | head -c 180)"
  fi

  res_reply=$(curl -sS -b "$COOKIE_JAR" --max-time 45 \
    -X POST "$REPORTS_URL/api/fleet/chat" \
    -H 'Content-Type: application/json' \
    -d '{"message":"Como estão os recursos?","preset":"ssdnodes-health"}' 2>/dev/null || true)
  if echo "$res_reply" | grep -qE 'fleet-structured|SSDNodes|Prometheus|sem inferência'; then
    ok "T-335 fleet resources structured reply"
  else
    bad "T-335 resources reply weak: $(echo "$res_reply" | head -c 200)"
  fi

  status_json=$(curl -sS -b "$COOKIE_JAR" --max-time 15 "$REPORTS_URL/api/fleet/copilot/status" 2>/dev/null || true)
  if echo "$status_json" | grep -qE 'structured-first|llm-default-structured-fast-path'; then
    ok "T-327 copilot status endpoint"
  else
    bad "T-327 status endpoint: $(echo "$status_json" | head -c 120)"
  fi

  if echo "$status_json" | grep -q '"thread_context":true'; then
    ok "T-336 thread context enabled in status"
  else
    bad "T-336 thread_context missing in status: $(echo "$status_json" | head -c 120)"
  fi

  vague_reply=$(curl -sS -b "$COOKIE_JAR" --max-time 45 \
    -X POST "$REPORTS_URL/api/fleet/chat" \
    -H 'Content-Type: application/json' \
    -d '{"message":"como ta o servidor?","preset":"ssdnodes-health"}' 2>/dev/null || true)
  if echo "$vague_reply" | grep -qE 'fleet-structured|SSDNodes|sem inferência'; then
    ok "T-337 vague server question uses structured fast path"
  else
    bad "T-337 vague reply slow or empty: $(echo "$vague_reply" | head -c 160)"
  fi

  scope_reply=$(curl -sS -b "$COOKIE_JAR" --max-time 15 \
    -X POST "$REPORTS_URL/api/fleet/chat" \
    -H 'Content-Type: application/json' \
    -d '{"message":"qual o uptime do nginx?","preset":"ssdnodes-health"}' 2>/dev/null || true)
  if echo "$scope_reply" | grep -qE 'fleet-meta|fora do escopo'; then
    ok "T-337 out-of-scope nginx boundary reply"
  else
    bad "T-337 scope boundary weak: $(echo "$scope_reply" | head -c 160)"
  fi
fi

# T-325 / UI delivery — assets live (não depende de kubectl)
css_asset=$(curl -sS --max-time 20 "$REPORTS_URL/assets/app.css" 2>/dev/null || true)
if echo "$css_asset" | grep -qE 'main--fleet-copilot|dnor-view-fleet-copilot|--dnor-copilot-column'; then
  ok "UI CSS T-325 ultrawide markers in app.css"
else
  bad "UI CSS missing T-325 markers (main--fleet-copilot / dnor-view-fleet-copilot)"
fi

js_asset=$(curl -sS --max-time 20 "$REPORTS_URL/assets/app.js" 2>/dev/null || true)
if echo "$js_asset" | grep -q 'ssdnodes-6a12f10c9ef11'; then
  bad "UI JS still contains legacy ssdnodes-6a12f10c9ef11"
else
  ok "UI JS free of ssdnodes-6a12f10c9ef11"
fi

if echo "$css_asset" | grep -q 'fleet-copilot-progress'; then
  ok "UI CSS T-327 loading progress bar"
else
  bad "UI CSS missing T-327 fleet-copilot-progress"
fi

if echo "$js_asset" | grep -q 'fleet-copilot-host-chip'; then
  ok "UI JS T-333 host mention chips"
else
  bad "UI JS missing fleet-copilot-host-chip"
fi

if echo "$js_asset" | grep -q 'This block should explain'; then
  bad "UI JS still contains placeholder copy (T-340)"
else
  ok "T-340 no placeholder copy in bundle"
fi

if echo "$css_asset" | grep -q 'dnor-alert-banner'; then
  ok "T-340 sticky error banner CSS"
else
  bad "T-340 missing dnor-alert-banner CSS"
fi

if echo "$css_asset" | grep -q 'dnor-overview-nav'; then
  ok "T-340-B overview section nav CSS"
else
  bad "T-340-B missing dnor-overview-nav CSS"
fi

if echo "$js_asset" | grep -q 'dnor-platform-fold'; then
  ok "T-340-B platform accordion in bundle"
else
  bad "T-340-B missing platform fold UI"
fi

if echo "$css_asset" | grep -q 'storage-row--pressure'; then
  ok "T-340-C storage pressure row CSS"
else
  bad "T-340-C missing storage-row--pressure CSS"
fi

if echo "$css_asset" | grep -q 'dnor-catalog-cta'; then
  ok "T-340-C catalog deep-link CTA CSS"
else
  bad "T-340-C missing dnor-catalog-cta CSS"
fi

if echo "$js_asset" | grep -q 'fleet-cluster-header'; then
  ok "T-340-C fleet cluster group headers"
else
  bad "T-340-C missing fleet-cluster-header UI"
fi

if echo "$js_asset" | grep -q 'dnor-view-fleet-copilot'; then
  ok "UI JS body class toggle (dnor-view-fleet-copilot)"
else
  bad "UI JS missing dnor-view-fleet-copilot"
fi

if echo "$js_asset" | grep -q 'ssdnodes-6a12f10c9ef11'; then
  ok "UI JS uses canonical SSDNodes hostname"
else
  bad "UI JS missing ssdnodes-6a12f10c9ef11"
fi

if echo "$js_asset" | grep -qE 'FleetCopilotPage|fleet-copilot-page'; then
  ok "UI bundle includes FleetCopilotPage"
else
  bad "UI bundle missing FleetCopilotPage component"
fi

if [[ -f "$ROOT_DIR/oci-k8s-cluster/kubeconfig_tunnel.yaml" ]]; then
  export KUBECONFIG="$ROOT_DIR/oci-k8s-cluster/kubeconfig_tunnel.yaml"
  if ! ss -tlnp 2>/dev/null | grep -q ':6445'; then
    ssh -o BatchMode=yes -o ConnectTimeout=10 -L 6445:127.0.0.1:6443 oci-k8s-master -N -f 2>/dev/null || true
    sleep 2
  fi
  if kubectl cluster-info --request-timeout=8s >/dev/null 2>&1; then
    if kubectl get secret fleet-copilot-creds -n default >/dev/null 2>&1; then
      ok "secret fleet-copilot-creds"
    else
      bad "secret fleet-copilot-creds missing"
    fi
    img=$(kubectl get deploy rs-observability-api-deployment -n default -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
    if [[ -n "$img" ]]; then
      ok "rs-observability-api image $img"
    else
      bad "rs-observability-api deployment"
    fi
  else
    echo "[ skip ] kubectl API unreachable — cluster checks skipped (tunnel 6445 or apiserver down)"
  fi
fi

echo ""
echo "=== Result: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
