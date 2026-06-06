#!/usr/bin/env bash
# codeql-scan.sh — CodeQL CLI no Jenkins SSDNodes (substitui .github/workflows/codeql.yml)
set -euo pipefail

REPO_ROOT="${CITOOLS_REPO_ROOT:-$(pwd)}"
cd "$REPO_ROOT"

CODEQL_HOME="${REPO_ROOT}/.codeql"
CODEQL_VERSION="${CODEQL_VERSION:-2.20.5}"
CODEQL_BUNDLE="codeql-bundle-linux64.tar.gz"

log() { printf '[codeql-scan] %s\n' "$*"; }

[[ -n "${GITHUB_TOKEN:-}" ]] || {
	log "GITHUB_TOKEN ausente — skip codeql"
	exit 0
}

if [[ ! -x "${CODEQL_HOME}/codeql/codeql" ]]; then
	log "baixando CodeQL bundle ${CODEQL_VERSION}"
	mkdir -p "${CODEQL_HOME}"
	curl -fsSL \
		"https://github.com/github/codeql-action/releases/download/codeql-bundle-v${CODEQL_VERSION}/${CODEQL_BUNDLE}" \
		-o "/tmp/${CODEQL_BUNDLE}"
	tar -xzf "/tmp/${CODEQL_BUNDLE}" -C "${CODEQL_HOME}"
fi

CODEQL="${CODEQL_HOME}/codeql/codeql"
export PATH="${CODEQL_HOME}/codeql:${PATH}"

REF="${CODEQL_REF:-${CHANGE_BRANCH:-${BRANCH_NAME:-main}}}"
SHA="${CODEQL_SHA:-${GIT_COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo HEAD)}}"
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
	printf '%s' "$GITHUB_TOKEN" | "$CODEQL" github upload-results \
		--sarif="${REPO_ROOT}/codeql-${lang}.sarif" \
		--ref="$REF" \
		--commit="$SHA" \
		--repository="$REPO" \
		--github-auth-stdin
}

run_lang javascript .
run_lang python .

log "CodeQL OK"
