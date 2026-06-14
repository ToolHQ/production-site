#!/usr/bin/env bash
# verify-branch-ci.sh — harness path-aware vs base branch (CI Jenkins)
set -euo pipefail

REPO_ROOT="${CITOOLS_REPO_ROOT:-$(cd "$(dirname "$0")/../../../.." && pwd)}"
cd "$REPO_ROOT"

BASE="${VERIFY_DIFF_BASE:-origin/main}"

if ! git rev-parse --verify "${BASE}^{commit}" >/dev/null 2>&1; then
	echo "[verify-branch-ci] ERRO: ${BASE} indisponível — confira fetch no Jenkinsfile" >&2
	git branch -a >&2 || true
	exit 1
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

export PATH="/usr/local/cargo/bin:/usr/local/bin:${PATH}"

bash components/ssdnodes/jenkins/scripts/ci-prep.sh "${paths[@]}"

exec ./tools/harness/verify.sh verify-changed --paths "${paths[@]}"
