#!/usr/bin/env bash
# changelog-update.sh — git-cliff no main (substitui auto-docs workflow)
set -euo pipefail

REPO_ROOT="${CITOOLS_REPO_ROOT:-$(pwd)}"
cd "$REPO_ROOT"

log() { printf '[changelog] %s\n' "$*"; }

BRANCH="${CITOOLS_BRANCH:-${BRANCH_NAME:-}}"
if [[ "$BRANCH" != "main" ]]; then
	log "branch=${BRANCH:-?} — skip (só main)"
	exit 0
fi

[[ -n "${GITHUB_TOKEN:-${GIT_PASS:-}}" ]] || {
	log "token ausente — skip push"
	exit 0
}

TOKEN="${GITHUB_TOKEN:-${GIT_PASS:-}}"
export GIT_CLIFF="${GIT_CLIFF:-git-cliff}"

if ! command -v git-cliff >/dev/null 2>&1; then
	log "git-cliff ausente — skip"
	exit 0
fi

git config user.name "${GIT_CLIFF_USER_NAME:-jenkins-ci[bot]}"
git config user.email "${GIT_CLIFF_USER_EMAIL:-jenkins-ci[bot]@users.noreply.github.com}"

git-cliff --config cliff.toml --output CHANGELOG.md

if git diff --quiet CHANGELOG.md; then
	log "CHANGELOG inalterado"
	exit 0
fi

git add CHANGELOG.md
git commit -m "docs(changelog): auto-update [skip ci]"

remote_url="$(git remote get-url origin)"
if [[ "$remote_url" == https://* ]]; then
	auth_url="${remote_url/https:\/\//https://x-access-token:${TOKEN}@}"
	git push "$auth_url" HEAD:main
else
	git push origin HEAD:main
fi

log "CHANGELOG pushed"
