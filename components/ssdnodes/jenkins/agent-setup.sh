#!/usr/bin/env bash
# agent-setup.sh — prepara o container rust do Jenkins (T-341)
# Instala deps mínimas para citools + harness verify-branch-ci.
set -euo pipefail

REPO_ROOT="${CITOOLS_REPO_ROOT:-${WORKSPACE:-$(pwd)}}"
export REPO_ROOT

log() { printf '[agent-setup] %s\n' "$*"; }

# --- PATH: citools (build abaixo) + sonar-scanner ---
export CARGO_HOME="${CARGO_HOME:-${REPO_ROOT}/.cargo}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${REPO_ROOT}/tools/citools/target}"
mkdir -p "$CARGO_HOME" "$CARGO_TARGET_DIR"

SONAR_SCANNER_HOME="${REPO_ROOT}/.sonar-scanner"
if [[ ! -x "${SONAR_SCANNER_HOME}/bin/sonar-scanner" ]]; then
	SONAR_SCANNER_VERSION="${SONAR_SCANNER_VERSION:-6.2.1.4610}"
	log "baixando sonar-scanner ${SONAR_SCANNER_VERSION}"
	curl -fsSL \
		"https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip" \
		-o /tmp/sonar-scanner.zip
	python3 -m zipfile -e /tmp/sonar-scanner.zip "${REPO_ROOT}"
	mv "${REPO_ROOT}/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64" "${SONAR_SCANNER_HOME}"
fi
export PATH="${SONAR_SCANNER_HOME}/bin:${PATH}"

# --- shellcheck (gate harness) ---
if ! command -v shellcheck >/dev/null 2>&1; then
	log "instalando shellcheck (apt)"
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq --no-install-recommends shellcheck ca-certificates git
fi

# --- citools ---
log "compilando citools (release)"
cd "${REPO_ROOT}/tools/citools"
cargo build --release --locked 2>/dev/null || cargo build --release
CITOOLS_BIN="${CARGO_TARGET_DIR}/release/citools"
export PATH="${CARGO_TARGET_DIR}/release:${PATH}"
install -m 0755 "${CITOOLS_BIN}" /usr/local/bin/citools 2>/dev/null || true

command -v citools >/dev/null
citools --version 2>/dev/null || true
log "agent pronto — citools + shellcheck + sonar-scanner"
