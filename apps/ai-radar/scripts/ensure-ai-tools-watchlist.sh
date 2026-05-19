#!/usr/bin/env bash
# Idempotent AI coding-tools watchlist (T-269).
#
# Ensures ≥1 source per vendor: Cursor, Copilot, Antigravity, Claude Code,
# OpenCode, OpenRouter — tagged metadata_json.watchlist = "ai-coding-tools".
#
# Usage:
#   API_URL=https://ai-radar.dnor.io ./scripts/ensure-ai-tools-watchlist.sh
#   DATABASE_URL=postgres://… ./scripts/ensure-ai-tools-watchlist.sh
#   DRY_RUN=1 ./scripts/ensure-ai-tools-watchlist.sh
#
# Requires: curl, jq; psql when DATABASE_URL is set.

set -euo pipefail

API_URL="${API_URL:-https://ai-radar.dnor.io}"
DRY_RUN="${DRY_RUN:-0}"
NAMESPACE="${AI_RADAR_NAMESPACE:-ai-radar}"
RUN_COLLECT_SMOKE="${RUN_COLLECT_SMOKE:-1}"
RUN_EXTRACT_SMOKE="${RUN_EXTRACT_SMOKE:-1}"
EXTRACT_LIMIT="${EXTRACT_LIMIT:-30}"

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
  local vendor="$2"
  shift 2
  local topics=("$@")
  jq -nc \
    --arg tier "$tier" \
    --arg vendor "$vendor" \
    --arg watchlist "ai-coding-tools" \
    --arg pack "ai-tools-watchlist" \
    --argjson topics "$(printf '%s\n' "${topics[@]}" | jq -R . | jq -s .)" \
    '{tier:$tier, vendor:$vendor, watchlist:$watchlist, topic:$topics, pack:$pack, curated_by:"T-269"}'
}

# name | source_type | url | poll_minutes | tier | vendor | topics_csv
read -r -d '' WATCHLIST_SOURCES <<'EOF' || true
watchlist-cursor-changelog|rss|https://cursor.com/changelog/rss.xml|120|core|cursor|agents,tools
watchlist-github-copilot|rss|https://github.blog/changelog/label/copilot/feed/|120|core|copilot|agents,tools
watchlist-antigravity-changelog|rss|https://www.gradually.ai/en/changelogs/antigravity/rss.xml|180|core|antigravity|agents,tools
watchlist-claude-code-releases|github_releases|https://github.com/anthropics/claude-code|240|core|claude-code|agents,tools
watchlist-opencode-releases|github_releases|https://github.com/sst/opencode|240|core|opencode|agents,tools
watchlist-openrouter-runner|github_repo|https://github.com/OpenRouterTeam/openrouter-runner|360|core|openrouter|models,pricing
EOF

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

validate_sources() {
  local name stype url poll _tier _vendor _topics code body failed=0
  while IFS='|' read -r name stype url poll _tier _vendor _topics; do
    [[ -z "$name" ]] && continue
    code="$(curl -sS -o /tmp/watchlist-chk -w '%{http_code}' -L --max-time 25 -A 'ai-radar-watchlist/1.0' "$url" 2>/dev/null || echo 000)"
    if [[ "$code" != "200" && "$code" != "301" && "$code" != "302" ]]; then
      log "WARN HTTP $code: $name ($url)"
      failed=$((failed + 1))
      continue
    fi
    if [[ "$stype" == "rss" ]]; then
      body="$(head -c 500 /tmp/watchlist-chk 2>/dev/null || true)"
      if ! echo "$body" | grep -qiE '<(rss|feed|rdf:RDF|<\?xml)'; then
        log "WARN not RSS/Atom: $name"
        failed=$((failed + 1))
        continue
      fi
    fi
    log "source OK: $name ($stype)"
  done <<< "$WATCHLIST_SOURCES"
  [[ "$failed" -eq 0 ]]
}

ensure_via_db() {
  local name stype url poll tier vendor topics_csv meta meta_sql name_sql url_sql stype_sql
  while IFS='|' read -r name stype url poll tier vendor topics_csv; do
    [[ -z "$name" ]] && continue
    IFS=',' read -r -a topics <<< "$topics_csv"
    meta="$(meta_json "$tier" "$vendor" "${topics[@]}")"
    meta_sql="$(sql_escape "$meta")"
    name_sql="$(sql_escape "$name")"
    url_sql="$(sql_escape "$url")"
    stype_sql="$(sql_escape "$stype")"
    psql_exec "INSERT INTO ai_radar.sources (name, source_type, url, enabled, poll_interval_minutes, metadata_json)
VALUES ('${name_sql}', '${stype_sql}', '${url_sql}', TRUE, ${poll}, '${meta_sql}'::jsonb)
ON CONFLICT (source_type, url) DO UPDATE SET
  name = EXCLUDED.name,
  enabled = TRUE,
  poll_interval_minutes = EXCLUDED.poll_interval_minutes,
  metadata_json = EXCLUDED.metadata_json;"
    log "upsert (db): $name [$vendor/$stype]"
  done <<< "$WATCHLIST_SOURCES"
}

ensure_via_api() {
  local name stype url poll tier vendor topics_csv meta body
  while IFS='|' read -r name stype url poll tier vendor topics_csv; do
    [[ -z "$name" ]] && continue
    if curl -fsS "${API_URL}/sources" | jq -e --arg n "$name" '.items[] | select(.name == $n)' >/dev/null 2>&1; then
      log "exists (api): $name — skip (use DATABASE_URL to upsert metadata)"
      continue
    fi
    IFS=',' read -r -a topics <<< "$topics_csv"
    meta="$(meta_json "$tier" "$vendor" "${topics[@]}")"
    body="$(jq -nc \
      --arg name "$name" --arg stype "$stype" --arg url "$url" --argjson poll "$poll" --argjson meta "$meta" \
      '{name:$name, source_type:$stype, url:$url, enabled:true, poll_interval_minutes:$poll, metadata_json:$meta}')"
    if [[ "$DRY_RUN" == "1" ]]; then
      log "[dry-run] POST /sources $name"
    else
      curl -fsS -X POST "${API_URL}/sources" -H 'Content-Type: application/json' -d "$body" >/dev/null
      log "created (api): $name"
    fi
  done <<< "$WATCHLIST_SOURCES"
}

collect_smoke() {
  if [[ "$RUN_COLLECT_SMOKE" != "1" ]] || [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  if ! command -v kubectl >/dev/null 2>&1; then
    log "kubectl missing — skip collect smoke"
    return 0
  fi
  local job="collect-watchlist-$(date +%s)"
  run kubectl -n "$NAMESPACE" create job --from=cronjob/ai-radar-collect "$job"
  log "collect job $job (timeout 15m)…"
  run kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$job" --timeout=900s
  run kubectl -n "$NAMESPACE" logs "job/$job" --tail=25
}

extract_smoke() {
  if [[ "$RUN_EXTRACT_SMOKE" != "1" ]] || [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  if command -v kubectl >/dev/null 2>&1; then
    local job="extract-watchlist-$(date +%s)"
    run kubectl -n "$NAMESPACE" create job --from=cronjob/ai-radar-extract "$job"
    log "extract job $job (timeout 20m)…"
    run kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$job" --timeout=1200s || true
    run kubectl -n "$NAMESPACE" logs "job/$job" --tail=15 || true
    return 0
  fi
  log "extract via API (limit=$EXTRACT_LIMIT)…"
  run curl -fsS -X POST "${API_URL}/extract/run" \
    -H 'Content-Type: application/json' \
    -d "{\"limit\":${EXTRACT_LIMIT}}" | jq .
}

summarize() {
  log "watchlist sources (enabled):"
  if ! curl -fsS "${API_URL}/sources/enabled" 2>/dev/null | jq -r \
    '.items[] | select(.metadata_json.watchlist == "ai-coding-tools") | "\(.name) vendor=\(.metadata_json.vendor // "?") type=\(.source_type) poll=\(.poll_interval_minutes)m"'; then
    log "API unavailable — query Postgres for watchlist rows if needed"
    return 0
  fi
  curl -fsS "${API_URL}/stats" 2>/dev/null | jq '{sources_enabled, raw_items_pending, embeddings}' || true
}

main() {
  log "API=$API_URL DATABASE_URL=${DATABASE_URL:+set} DRY_RUN=$DRY_RUN"
  if status="$(curl -fsS "${API_URL}/health" 2>/dev/null | jq -r '.status')" && [[ -n "$status" ]]; then
    log "health: $status"
  else
    log "WARN: API health check failed — continuing if DATABASE_URL set"
    [[ -n "${DATABASE_URL:-}" ]] || exit 1
  fi

  validate_sources

  if [[ -n "${DATABASE_URL:-}" ]]; then
    ensure_via_db
  else
    log "DATABASE_URL unset — create-only via API"
    ensure_via_api
  fi

  collect_smoke
  extract_smoke
  summarize
}

main "$@"
