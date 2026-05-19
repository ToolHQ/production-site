#!/usr/bin/env bash
# Idempotent curated AI vendor RSS pack (T-268).
#
# Ensures ≥8 tier-`core` RSS sources, tags metadata (`tier`, `topic`, `pack`),
# and disables generic demo/smoke feeds per docs/AI-RADAR-SOURCES.md.
#
# Usage:
#   API_URL=https://ai-radar.dnor.io ./scripts/ensure-ai-rss-sources.sh
#   DATABASE_URL=postgres://… ./scripts/ensure-ai-rss-sources.sh   # preferred (upsert + disable)
#   DRY_RUN=1 ./scripts/ensure-ai-rss-sources.sh                   # print actions only
#
# Requires: curl, jq; psql when DATABASE_URL is set.

set -euo pipefail

API_URL="${API_URL:-https://ai-radar.dnor.io}"
DRY_RUN="${DRY_RUN:-0}"
NAMESPACE="${AI_RADAR_NAMESPACE:-ai-radar}"
RUN_COLLECT_SMOKE="${RUN_COLLECT_SMOKE:-1}"

log() { printf '→ %s\n' "$*"; }

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] $*"
  else
    "$@"
  fi
}

meta_json() {
  local tier="$1"
  shift
  local topics=("$@")
  jq -nc --arg tier "$tier" --arg pack "ai-vendor-rss" \
    --argjson topics "$(printf '%s\n' "${topics[@]}" | jq -R . | jq -s .)" \
    '{tier:$tier, topic:$topics, pack:$pack, curated_by:"T-268"}'
}

# name | url | poll_minutes | tier | topic1[,topic2…]
read -r -d '' CORE_SOURCES <<'EOF' || true
vendor-openai|https://openai.com/news/rss.xml|180|core|models
vendor-google-ai|https://blog.google/technology/ai/rss/|180|core|models
vendor-huggingface|https://huggingface.co/blog/feed.xml|120|core|models
vendor-deepmind|https://www.deepmind.com/blog/rss.xml|240|core|models
vendor-aws-ml|https://aws.amazon.com/blogs/machine-learning/feed/|240|core|infra,models
vendor-langchain|https://blog.langchain.com/rss.xml|180|core|agents
vendor-interconnects|https://www.interconnects.ai/feed|360|core|models,industry
vendor-simon-willison|https://simonwillison.net/atom/everything/|120|core|agents,tools
vendor-latent-space|https://www.latent.space/feed|360|vendor|agents,models
EOF

DISABLE_SOURCES=(
  smoke-t173-hn
  demo-lobsters
  demo-hn-frontpage
  smoke-direct
)

PATCH_SOURCES=(
  "demo-pragmatic-engineer|vendor|industry,agents"
  "smoke-adoption-ollama|core|models,infra"
)

psql_exec() {
  local sql="$1"
  if [[ -z "${DATABASE_URL:-}" ]]; then
    return 1
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    log "[dry-run] psql: ${sql//$'\n'/ }"
    return 0
  fi
  psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "$sql" >/dev/null
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

ensure_via_db() {
  local name url poll tier topics_csv meta
  while IFS='|' read -r name url poll tier topics_csv; do
    [[ -z "$name" ]] && continue
    IFS=',' read -r -a topics <<< "$topics_csv"
    meta="$(meta_json "$tier" "${topics[@]}")"
    local meta_sql name_sql url_sql
    meta_sql="$(sql_escape "$meta")"
    name_sql="$(sql_escape "$name")"
    url_sql="$(sql_escape "$url")"
    psql_exec "INSERT INTO ai_radar.sources (name, source_type, url, enabled, poll_interval_minutes, metadata_json)
VALUES ('${name_sql}', 'rss', '${url_sql}', TRUE, ${poll}, '${meta_sql}'::jsonb)
ON CONFLICT (source_type, url) DO UPDATE SET
  name = EXCLUDED.name,
  enabled = TRUE,
  poll_interval_minutes = EXCLUDED.poll_interval_minutes,
  metadata_json = EXCLUDED.metadata_json;"
    log "upsert (db): $name [$tier]"
  done <<< "$CORE_SOURCES"
}

ensure_via_api() {
  local name url poll tier topics_csv meta body
  while IFS='|' read -r name url poll tier topics_csv; do
    [[ -z "$name" ]] && continue
    if curl -fsS "${API_URL}/sources" | jq -e --arg n "$name" '.items[] | select(.name == $n)' >/dev/null 2>&1; then
      log "exists (api): $name — skip (use DATABASE_URL to upsert metadata)"
      continue
    fi
    IFS=',' read -r -a topics <<< "$topics_csv"
    meta="$(meta_json "$tier" "${topics[@]}")"
    body="$(jq -nc \
      --arg name "$name" --arg url "$url" --argjson poll "$poll" --argjson meta "$meta" \
      '{name:$name, source_type:"rss", url:$url, enabled:true, poll_interval_minutes:$poll, metadata_json:$meta}')"
    if [[ "$DRY_RUN" == "1" ]]; then
      log "[dry-run] POST /sources $name"
    else
      curl -fsS -X POST "${API_URL}/sources" -H 'Content-Type: application/json' -d "$body" >/dev/null
      log "created (api): $name"
    fi
  done <<< "$CORE_SOURCES"
}

disable_experimental() {
  local name meta escaped meta_sql name_sql
  meta="$(meta_json experimental general)"
  meta_sql="$(sql_escape "$meta")"
  for name in "${DISABLE_SOURCES[@]}"; do
    if [[ -n "${DATABASE_URL:-}" ]]; then
      name_sql="$(sql_escape "$name")"
      psql_exec "UPDATE ai_radar.sources SET enabled = FALSE, metadata_json = COALESCE(metadata_json, '{}'::jsonb) || '${meta_sql}'::jsonb WHERE name = '${name_sql}';"
      log "disabled (db): $name"
    else
      log "skip disable $name — set DATABASE_URL to patch existing sources"
    fi
  done
}

patch_existing_metadata() {
  local row name tier topics_csv meta meta_sql name_sql
  for row in "${PATCH_SOURCES[@]}"; do
    IFS='|' read -r name tier topics_csv <<< "$row"
    IFS=',' read -r -a topics <<< "$topics_csv"
    meta="$(meta_json "$tier" "${topics[@]}")"
    meta_sql="$(sql_escape "$meta")"
    if [[ -n "${DATABASE_URL:-}" ]]; then
      name_sql="$(sql_escape "$name")"
      psql_exec "UPDATE ai_radar.sources SET metadata_json = COALESCE(metadata_json, '{}'::jsonb) || '${meta_sql}'::jsonb WHERE name = '${name_sql}';"
      log "metadata (db): $name → tier=$tier"
    fi
  done
}

validate_feeds() {
  local name url poll _tier _topics code
  local failed=0
  while IFS='|' read -r name url poll _tier _topics; do
    [[ -z "$name" ]] && continue
    code="$(curl -sS -o /dev/null -w '%{http_code}' -L --max-time 20 -A 'ai-radar-ensure-sources/1.0' "$url" 2>/dev/null || echo 000)"
    if [[ "$code" != "200" ]]; then
      log "WARN feed HTTP $code: $name ($url)"
      failed=$((failed + 1))
    else
      log "feed OK: $name"
    fi
  done <<< "$CORE_SOURCES"
  [[ "$failed" -eq 0 ]]
}

collect_smoke() {
  if [[ "$RUN_COLLECT_SMOKE" != "1" ]] || [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    log "kubectl missing — skip collect smoke"
    return 0
  fi
  local job="collect-rss-pack-$(date +%s)"
  run kubectl -n "$NAMESPACE" create job --from=cronjob/ai-radar-collect "$job"
  log "collect job $job (timeout 15m)…"
  run kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$job" --timeout=900s
  run kubectl -n "$NAMESPACE" logs "job/$job" --tail=30
}

summarize() {
  log "enabled RSS sources:"
  curl -fsS "${API_URL}/sources/enabled" | jq -r '.items[] | select(.source_type=="rss") | "\(.name) tier=\(.metadata_json.tier // "?") poll=\(.poll_interval_minutes)m"'
  curl -fsS "${API_URL}/stats" | jq '{sources_enabled, raw_items_pending, embeddings}'
}

main() {
  log "API=$API_URL DATABASE_URL=${DATABASE_URL:+set} DRY_RUN=$DRY_RUN"
  local status
  status="$(curl -fsS "${API_URL}/health" | jq -r '.status')"
  log "health: $status"

  validate_feeds

  if [[ -n "${DATABASE_URL:-}" ]]; then
    ensure_via_db
    disable_experimental
    patch_existing_metadata
  else
    log "DATABASE_URL unset — create-only via API (disable/patch skipped)"
    ensure_via_api
  fi

  collect_smoke
  summarize
}

main "$@"
