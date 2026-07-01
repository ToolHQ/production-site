#!/usr/bin/env bash
# configure_github_ci_protection.sh — branch protection + webhook Jenkins (T-345)
#
# Uso:
#   bash scripts/harness/configure_github_ci_protection.sh
#   bash scripts/harness/configure_github_ci_protection.sh --dry-run
#   GITHUB_WEBHOOK_SECRET=... bash scripts/harness/configure_github_ci_protection.sh
#
# Requer: gh auth login (admin repo ou bypass rules)
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-ToolHQ/production-site}"
BRANCH="${GITHUB_DEFAULT_BRANCH:-main}"
STATUS_CONTEXT="${GITHUB_STATUS_CONTEXT:-jenkins/citools}"
JENKINS_WEBHOOK_URL="${JENKINS_WEBHOOK_URL:-https://jenkins.ssdnodes.dnor.io/github-webhook/}"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run) DRY_RUN=true; shift ;;
  --repo)
    REPO="${2:?--repo requires owner/name}"
    shift 2
    ;;
  --context)
    STATUS_CONTEXT="${2:?--context requires name}"
    shift 2
    ;;
  -h | --help)
    cat <<EOF
Uso: $0 [--dry-run] [--repo owner/name] [--context jenkins/...]

Exemplos:
  $0 --repo ToolHQ/production-site --context jenkins/citools
  $0 --repo dnorio/agent-meter --context jenkins/agent-meter
EOF
    exit 0
    ;;
  *) echo "argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

log() { printf '[configure-github-ci] %s\n' "$*"; }

gh auth status >/dev/null 2>&1 || {
  echo "❌ gh auth login necessário" >&2
  exit 2
}

WEBHOOK_SECRET="${GITHUB_WEBHOOK_SECRET:-$(openssl rand -hex 32)}"

protection_payload=$(STATUS_CONTEXT="$STATUS_CONTEXT" python3 - <<'PY'
import json, os
print(json.dumps({
    "required_status_checks": {
        "strict": True,
        "contexts": [os.environ["STATUS_CONTEXT"]],
    },
    "enforce_admins": False,
    "required_pull_request_reviews": None,
    "restrictions": None,
    "required_linear_history": False,
    "allow_force_pushes": False,
    "allow_deletions": False,
}))
PY
)

hook_payload=$(python3 - <<PY
import json
print(json.dumps({
    "name": "web",
    "active": True,
    "events": ["push", "pull_request", "create", "delete"],
    "config": {
        "url": "${JENKINS_WEBHOOK_URL}",
        "content_type": "json",
        "secret": "${WEBHOOK_SECRET}",
        "insecure_ssl": "0",
    },
}))
PY
)

log "Repo: ${REPO} | branch: ${BRANCH} | required check: ${STATUS_CONTEXT}"
log "Webhook: ${JENKINS_WEBHOOK_URL}"

if [[ "$DRY_RUN" == true ]]; then
  log "[dry-run] protection payload:"
  echo "$protection_payload" | python3 -m json.tool
  log "[dry-run] webhook secret (primeiros 8): ${WEBHOOK_SECRET:0:8}..."
  exit 0
fi

log "Aplicando branch protection..."
gh api --method PUT "repos/${REPO}/branches/${BRANCH}/protection" \
  --input - <<<"$protection_payload"

log "Procurando webhook Jenkins existente..."
existing_id=$(gh api "repos/${REPO}/hooks" --jq ".[] | select(.config.url==\"${JENKINS_WEBHOOK_URL}\") | .id" | head -1 || true)

if [[ -n "${existing_id:-}" ]]; then
  log "Atualizando webhook id=${existing_id}..."
  gh api --method PATCH "repos/${REPO}/hooks/${existing_id}" \
    --input - <<<"$(python3 - <<PY
import json
p = json.loads('''${hook_payload}''')
print(json.dumps({"config": p["config"], "events": p["events"], "active": True}))
PY
)"
else
  log "Criando webhook..."
  gh api --method POST "repos/${REPO}/hooks" --input - <<<"$hook_payload"
fi

log "✓ Branch protection + webhook configurados"
log "⚠️  UFW SSDNodes: aplicar allowlist GitHub hooks (T-345):"
log "   bash oci-k8s-cluster/scripts/hardening/ufw_manager.sh --host ssdnodes-6a12f10c9ef11 --apply"
log "⚠️  Salve GITHUB_WEBHOOK_SECRET no Jenkins Secret (github-webhook-secret):"
log "   export GITHUB_WEBHOOK_SECRET='${WEBHOOK_SECRET}'"
log "   bash oci-k8s-cluster/scripts/ssdnodes/setup_jenkins_ci_jobs.sh --update-home-creds"
