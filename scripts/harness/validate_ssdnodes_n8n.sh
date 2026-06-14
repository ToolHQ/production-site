#!/usr/bin/env bash
# validate_ssdnodes_n8n.sh — smoke TLS + healthz + basic auth (T-361)
set -euo pipefail

N8N_URL="${N8N_URL:-https://n8n.ssdnodes.dnor.io}"
REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
CREDS_FILE="${N8N_CREDS_FILE:-${HOME}/ssdnodes-n8n-credentials.txt}"
EXPECTED_IMAGE="${EXPECTED_N8N_IMAGE:-docker.n8n.io/n8nio/n8n:1.97.1}"

ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; FAIL=1; }

FAIL=0
echo "=== validate_ssdnodes_n8n (T-361) ==="

# Health (may require basic auth — 401 still proves TLS + routing)
http_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$N8N_URL/healthz" 2>/dev/null || echo "000")
case "$http_code" in
  200) ok "n8n /healthz 200 ($N8N_URL)" ;;
  401) ok "n8n /healthz protegido (401 — basic auth ativo)" ;;
  *) bad "n8n /healthz HTTP $http_code (esperado 200 ou 401)" ;;
esac

# TLS cert valid
if curl -fsS --max-time 15 "$N8N_URL/" -o /dev/null 2>/dev/null; then
  ok "n8n HTTPS root ($N8N_URL)"
elif [[ "$http_code" == "401" ]]; then
  ok "n8n HTTPS (401 sem credenciais — OK)"
else
  bad "n8n HTTPS indisponível — DNS/cert/deploy pendente?"
fi

# Optional basic auth check
if [[ -f "$CREDS_FILE" ]]; then
  user=$(grep -oP 'Basic auth user: \K.*' "$CREDS_FILE" 2>/dev/null || true)
  pass=$(grep -oP 'Basic auth pass: \K.*' "$CREDS_FILE" 2>/dev/null | awk '{print $1}' || true)
  if [[ -n "$user" && -n "$pass" ]]; then
    auth_code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 -u "$user:$pass" "$N8N_URL/healthz" 2>/dev/null || echo "000")
    if [[ "$auth_code" == "200" ]]; then
      ok "Basic auth válido (healthz 200 com credenciais)"
    else
      bad "Basic auth falhou (HTTP $auth_code)"
    fi
  fi
fi

# Cluster
if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl get pods -n n8n -o jsonpath='{.items[0].status.phase}' 2>/dev/null" | grep -q Running; then
  ok "Pod n8n Running no cluster"
  runtime_img=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
    "kubectl get deploy n8n -n n8n -o jsonpath='{.spec.template.spec.containers[0].image}'" 2>/dev/null || true)
  if [[ "$runtime_img" == "$EXPECTED_IMAGE" ]]; then
    ok "Imagem IaC ($runtime_img)"
  else
    bad "Imagem drift: runtime=$runtime_img expected=$EXPECTED_IMAGE"
  fi
else
  bad "Pod n8n não Running"
fi

if [[ "${FAIL:-0}" -eq 0 ]]; then
  echo "PASS validate_ssdnodes_n8n"
else
  echo "FAIL validate_ssdnodes_n8n"
  exit 1
fi
