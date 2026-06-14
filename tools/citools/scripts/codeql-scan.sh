#!/usr/bin/env bash
# codeql-scan.sh — CodeQL CLI no Jenkins SSDNodes (substitui .github/workflows/codeql.yml)
set -euo pipefail

REPO_ROOT="${CITOOLS_REPO_ROOT:-$(pwd)}"
cd "$REPO_ROOT"

log() { printf '[codeql-scan] %s\n' "$*"; }

[[ -n "${GITHUB_TOKEN:-}" ]] || {
	log "GITHUB_TOKEN ausente — skip codeql"
	exit 0
}

CODEQL="${CODEQL_BIN:-$(command -v codeql 2>/dev/null || true)}"
[[ -x "$CODEQL" ]] || {
	log "codeql CLI ausente — skip (agent-setup deveria instalar)"
	exit 0
}

REF="${CODEQL_REF:-${CHANGE_BRANCH:-${BRANCH_NAME:-main}}}"
SHA="${CODEQL_SHA:-${GIT_COMMIT:-}}"
[[ ${#SHA} -eq 40 ]] || SHA="$(git rev-parse HEAD 2>/dev/null || true)"
[[ ${#SHA} -eq 40 ]] || {
	log "commit SHA indisponível — skip codeql upload"
	exit 0
}
if [[ "$REF" != refs/* ]]; then
	REF="refs/heads/${REF}"
fi
REPO="${GITHUB_REPOSITORY:-ToolHQ/production-site}"

run_lang() {
	local lang=$1 src_root=$2
	local db="${REPO_ROOT}/.codeql-db-${lang}"
	rm -rf "$db"
	log "database create (${lang})"
	"$CODEQL" database create "$db" \
		--language="$lang" \
		--source-root="$src_root" \
		--overwrite
	log "database analyze (${lang})"
	"$CODEQL" database analyze "$db" \
		--format=sarif-latest \
		--output="${REPO_ROOT}/codeql-${lang}.sarif" \
		--sarif-category="/language:${lang}"
	log "upload sarif (${lang})"
	export GITHUB_TOKEN
	"$CODEQL" github upload-results \
		--sarif="${REPO_ROOT}/codeql-${lang}.sarif" \
		--ref="$REF" \
		--commit="$SHA" \
		--repository="$REPO"
}

ec=0
run_lang javascript . &
pid_js=$!
run_lang python . &
pid_py=$!
wait "$pid_js" || ec=1
wait "$pid_py" || ec=1
[[ "$ec" -eq 0 ]] || exit "$ec"

log "CodeQL OK"
