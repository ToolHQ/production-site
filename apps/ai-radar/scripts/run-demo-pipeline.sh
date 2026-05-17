#!/usr/bin/env bash
# Enfileira collect → extract → score → digest para demonstração no Operator Console.
# Uso: API_URL=https://ai-radar.dnor.io ./scripts/run-demo-pipeline.sh
# Requer: curl, jq, kubectl (opcional para jobs no cluster).

set -euo pipefail

API_URL="${API_URL:-https://ai-radar.dnor.io}"
EXTRACT_LIMIT="${EXTRACT_LIMIT:-50}"
EXTRACT_ROUNDS="${EXTRACT_ROUNDS:-3}"
NAMESPACE="${AI_RADAR_NAMESPACE:-ai-radar}"
USE_K8S_JOBS="${USE_K8S_JOBS:-1}"

log() { printf '→ %s\n' "$*"; }

api_post() {
  local path="$1"
  local body="${2:-{}}"
  curl -fsS -X POST "${API_URL}${path}" \
    -H 'Content-Type: application/json' \
    -d "$body"
}

ensure_source() {
  local name="$1"
  local type="$2"
  local url="$3"
  local poll="${4:-30}"
  if curl -fsS "${API_URL}/sources" | jq -e --arg n "$name" '.items[] | select(.name == $n)' >/dev/null; then
    log "fonte já existe: $name"
    return 0
  fi
  log "criando fonte: $name ($type)"
  api_post /sources "$(jq -nc \
    --arg name "$name" --arg type "$type" --arg url "$url" --argjson poll "$poll" \
    '{name:$name, source_type:$type, url:$url, enabled:true, poll_interval_minutes:$poll}')"
}

run_k8s_job() {
  local cron="$1"
  local suffix="$2"
  local job="${cron}-${suffix}-$(date +%s)"
  if ! command -v kubectl >/dev/null 2>&1 || [[ "$USE_K8S_JOBS" != "1" ]]; then
    return 1
  fi
  kubectl -n "$NAMESPACE" create job --from="cronjob/${cron}" "$job" >/dev/null
  log "job $job (aguardando até 20m)…"
  kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$job" --timeout=1200s
  kubectl -n "$NAMESPACE" logs "job/$job" --tail=20
}

log "API: $API_URL"
curl -fsS "${API_URL}/health" | jq -r '.status' | xargs -I{} log "health: {}"

# Fontes demo (RSS confiável + variedade para o digest)
ensure_source "demo-hn-frontpage" "rss" "https://hnrss.org/frontpage" 30
ensure_source "demo-lobsters" "rss" "https://lobste.rs/rss" 60
ensure_source "demo-pragmatic-engineer" "rss" "https://newsletter.pragmaticengineer.com/feed" 120

if run_k8s_job "ai-radar-collect" "demo"; then
  :
else
  log "collect via API indisponível — use CronJob ou CLI local"
fi

if run_k8s_job "ai-radar-extract" "demo"; then
  :
else
  for ((i = 1; i <= EXTRACT_ROUNDS; i++)); do
    log "extract round $i/$EXTRACT_ROUNDS (limit=$EXTRACT_LIMIT)"
    api_post /extract/run "{\"limit\":${EXTRACT_LIMIT}}" | jq .
  done
fi

if run_k8s_job "ai-radar-score" "demo"; then
  :
else
  api_post /score/run '{"limit":100,"stale_hours":1}' | jq .
fi

DIGEST_ID=$(api_post /digest/run '{"kind":"weekly"}' | jq -r .digest_id)
log "digest_id=$DIGEST_ID"
log "console: ${API_URL}/#/digests/${DIGEST_ID}"
curl -fsS "${API_URL}/stats" | jq .
curl -fsS "${API_URL}/digests" | jq '{count, latest: .items[0].id}'
