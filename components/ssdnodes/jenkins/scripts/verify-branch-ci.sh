#!/usr/bin/env bash
# verify-branch-ci.sh — harness path-aware vs base branch (CI Jenkins)
#
# Local: verify-changed usa working tree (staged/unstaged).
# CI:   diff limpo checkout → compara HEAD vs origin/main (ou VERIFY_DIFF_BASE).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$REPO_ROOT"

BASE="${VERIFY_DIFF_BASE:-origin/main}"
FETCH="${VERIFY_FETCH_BASE:-1}"

if [[ "$FETCH" == "1" ]]; then
	git fetch --depth=1 origin "${BASE#origin/}" 2>/dev/null \
		|| git fetch --depth=1 origin main 2>/dev/null \
		|| true
fi

if ! git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1; then
	echo "[verify-branch-ci] base ${BASE} indisponível — fallback origin/main" >&2
	BASE="origin/main"
fi

mapfile -t paths < <(
	git diff --name-only "${BASE}...HEAD" --diff-filter=ACMRTUXB | awk 'NF'
)

if [[ ${#paths[@]} -eq 0 ]]; then
	echo "[verify-branch-ci] nenhum path alterado vs ${BASE}"
	exit 0
fi

echo "[verify-branch-ci] ${#paths[@]} path(s) vs ${BASE}:"
printf '  %s\n' "${paths[@]}"

exec ./tools/harness/verify.sh verify-changed --paths "${paths[@]}"
