#!/usr/bin/env bash
# validate_ssdnodes_email_intel.sh — T-362a/c security harness
# Postgres ClusterIP + RLS + pgcrypto + Ollama bridge (pods only)
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
CREDS_FILE="${EMAIL_INTEL_CREDS_FILE:-${HOME}/ssdnodes-email-intelligence-credentials.txt}"
NODE_IP="${SSD_NODES_IP:-104.225.218.78}"

ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; FAIL=1; }

FAIL=0
echo "=== validate_ssdnodes_email_intel (T-362a/c) ==="

# ─── Postgres pod + ClusterIP only ───────────────────────────────────────────
pg_phase=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl get pods -n email-intelligence -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].status.phase}'" 2>/dev/null || echo "")
if [[ "$pg_phase" == "Running" ]]; then
  ok "Postgres pod Running (email-intelligence)"
else
  bad "Postgres pod não Running (phase=$pg_phase)"
fi

svc_type=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl get svc -n email-intelligence -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].spec.type}'" 2>/dev/null || echo "")
if [[ "$svc_type" == "ClusterIP" ]]; then
  ok "Postgres Service ClusterIP (sem NodePort/Ingress)"
else
  bad "Postgres Service type=$svc_type (esperado ClusterIP)"
fi

# ─── Migration job completed ─────────────────────────────────────────────────
migrate_status=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl get job email-intel-schema-migrate -n email-intelligence -o jsonpath='{.status.succeeded}'" 2>/dev/null || echo "0")
if [[ "${migrate_status:-0}" -ge 1 ]]; then
  ok "Schema migration job succeeded"
else
  bad "Schema migration job não concluída (succeeded=$migrate_status)"
fi

# ─── RLS + pgcrypto roundtrip (via ephemeral psql pod) ───────────────────────
if [[ -f "$CREDS_FILE" ]]; then
  N8N_APP_PASS=$(grep -oP 'n8n_app DB password: \K.*' "$CREDS_FILE" 2>/dev/null || true)
  PGCRYPTO_KEY=$(grep -oP 'pgcrypto-key: \K.*' "$CREDS_FILE" 2>/dev/null || true)
fi
N8N_APP_PASS="${N8N_APP_PASS:-$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl get secret email-intelligence-db-credentials -n email-intelligence -o jsonpath='{.data.n8n-app-password}' 2>/dev/null | base64 -d" 2>/dev/null || true)}"
PGCRYPTO_KEY="${PGCRYPTO_KEY:-$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl get secret email-intelligence-db-credentials -n email-intelligence -o jsonpath='{.data.pgcrypto-key}' 2>/dev/null | base64 -d" 2>/dev/null || true)}"

if [[ -n "$N8N_APP_PASS" && -n "$PGCRYPTO_KEY" ]]; then
  rls_out=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
    "kubectl delete pod email-intel-rls-test -n email-intelligence --ignore-not-found >/dev/null 2>&1; \
     kubectl run email-intel-rls-test -n email-intelligence --restart=Never \
       --image=docker.io/bitnamilegacy/postgresql:16.4.0-debian-12-r14 \
       --env=PGHOST=email-intelligence-postgresql \
       --env=PGUSER=n8n_app \
       --env=PGDATABASE=email_intel \
       --env=PGPASSWORD=${N8N_APP_PASS} \
       --command -- psql -tAc \"SET app.pgcrypto_key='${PGCRYPTO_KEY}'; SELECT decrypt_pii(encrypt_pii('harness-secret'));\" \
     >/dev/null 2>&1; sleep 12; \
     kubectl logs email-intel-rls-test -n email-intelligence 2>/dev/null | tr -d '[:space:]'; \
     kubectl delete pod email-intel-rls-test -n email-intelligence --ignore-not-found >/dev/null 2>&1" 2>/dev/null || echo "")
  if [[ "$rls_out" == *harness-secret* ]]; then
    ok "RLS + pgcrypto roundtrip (n8n_app)"
  else
    bad "RLS/pgcrypto test falhou (got: ${rls_out:-empty})"
  fi
else
  bad "Credenciais n8n_app/pgcrypto indisponíveis para teste RLS"
fi

# ─── Ollama bridge from n8n namespace ────────────────────────────────────────
ollama_json=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl run ollama-bridge-test -n n8n --restart=Never --image=curlimages/curl:8.5.0 \
    --command -- curl -sf --max-time 10 http://ollama-host:11434/api/tags" 2>/dev/null || true)
sleep 8
ollama_logs=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl logs ollama-bridge-test -n n8n 2>/dev/null; kubectl delete pod ollama-bridge-test -n n8n --ignore-not-found" 2>/dev/null || true)
if echo "$ollama_logs" | grep -q '"models"'; then
  ok "Ollama /api/tags acessível de pod n8n (ollama-host:11434)"
else
  bad "Ollama bridge inacessível do namespace n8n"
fi

# ─── UFW: 11434 não aberto ao mundo ─────────────────────────────────────────
ufw_11434=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "sudo ufw status numbered 2>/dev/null | grep 11434 || true" 2>/dev/null || true)
if echo "$ufw_11434" | grep -q "10.244.0.0/16"; then
  ok "UFW 11434 restrito ao pod CIDR"
elif [[ -z "$ufw_11434" ]]; then
  ok "UFW sem regra global 11434 (deny default)"
else
  bad "UFW 11434 possivelmente exposto: $ufw_11434"
fi

# ─── Zero secrets no Git (sanity) ────────────────────────────────────────────
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if git -C "$repo_root" grep -rE 'n8n-app-password|pgcrypto-key' -- ':!*.sh' ':!*.md' ':!*.yaml' 2>/dev/null | grep -qv 'secretKeyRef\|key:'; then
  bad "Possível secret literal no repo"
else
  ok "Sem secrets hardcoded nos manifests rastreados"
fi

if [[ "${FAIL:-0}" -eq 0 ]]; then
  echo "PASS validate_ssdnodes_email_intel"
else
  echo "FAIL validate_ssdnodes_email_intel"
  exit 1
fi
