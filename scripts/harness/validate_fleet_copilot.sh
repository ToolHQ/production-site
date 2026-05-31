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

if ssh -o ConnectTimeout=10 -o BatchMode=yes ssdnodes-monstro \
  "curl -fsS --max-time 5 http://127.0.0.1:11434/api/tags >/dev/null && \
   systemctl is-active fleet-ops-gateway >/dev/null && \
   sudo ufw status | grep -q '11434.*DENY'"; then
  ok "monstro ollama localhost + gateway + ufw deny 11434"
else
  bad "monstro stack check"
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
fi

if [[ -f "$ROOT_DIR/oci-k8s-cluster/kubeconfig_tunnel.yaml" ]]; then
  export KUBECONFIG="$ROOT_DIR/oci-k8s-cluster/kubeconfig_tunnel.yaml"
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
fi

echo ""
echo "=== Result: $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
