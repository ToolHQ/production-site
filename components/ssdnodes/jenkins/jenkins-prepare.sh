#!/usr/bin/env bash
# jenkins-prepare.sh — fetch origin/main pós-checkout (clone shallow multibranch)
set -euo pipefail

git config --global --add safe.directory "${WORKSPACE}"
git fetch --no-tags \
	"https://${GIT_USER}:${GIT_PASS}@github.com/ToolHQ/production-site.git" \
	+refs/heads/main:refs/remotes/origin/main
git rev-parse --verify origin/main^{commit}
