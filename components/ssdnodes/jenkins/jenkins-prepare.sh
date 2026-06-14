#!/usr/bin/env bash
# jenkins-prepare.sh — fetch origin/main pós-checkout (clone shallow multibranch)
set -euo pipefail

git config --global --add safe.directory "${WORKSPACE}"
git fetch --no-tags \
	"https://${GIT_USER}:${GIT_PASS}@github.com/ToolHQ/production-site.git" \
	+refs/heads/main:refs/remotes/origin/main
git rev-parse --verify 'origin/main^{commit}'

mapfile -t _paths < <(git diff --name-only origin/main...HEAD --diff-filter=ACMRTUXB | awk 'NF')
: >"${WORKSPACE}/.citools-changed-paths"
if [[ ${#_paths[@]} -gt 0 ]]; then
	printf '%s\n' "${_paths[@]}" >"${WORKSPACE}/.citools-changed-paths"
fi
echo "[jenkins-prepare] ${#_paths[@]} path(s) vs origin/main → .citools-changed-paths"
