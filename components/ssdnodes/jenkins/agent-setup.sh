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
# Linux zip não inclui JRE embarcado; o script default aponta JAVA_HOME para jre/ inexistente.
if [[ -f "${SONAR_SCANNER_HOME}/bin/sonar-scanner" ]]; then
	sed -i 's/use_embedded_jre=true/use_embedded_jre=false/' "${SONAR_SCANNER_HOME}/bin/sonar-scanner"
fi
chmod -R a+rx "${SONAR_SCANNER_HOME}/bin" 2>/dev/null || true
find "${SONAR_SCANNER_HOME}" -type f \( -name 'sonar-scanner' -o -name 'sonar-scanner-debug' \) -exec chmod +x {} + 2>/dev/null || true
export PATH="${SONAR_SCANNER_HOME}/bin:${PATH}"

# --- deps harness (shellcheck, yamllint, git, shfmt, node) ---
need_apt=0
for cmd in shellcheck yamllint git java curl jq; do
	command -v "$cmd" >/dev/null 2>&1 || need_apt=1
done
if [[ "$need_apt" == "1" ]]; then
	log "instalando shellcheck, yamllint, git, openjdk, curl, jq (apt)"
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq --no-install-recommends \
		shellcheck yamllint git ca-certificates openjdk-17-jre-headless curl gnupg jq
fi

if ! command -v node >/dev/null 2>&1; then
	need_node=1
else
	need_node=0
	ver="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
	[[ "$ver" -lt 20 ]] && need_node=1
fi
if [[ "$need_node" == "1" ]]; then
	log "instalando Node.js 20 (nodesource)"
	curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
	apt-get install -y -qq nodejs
fi

if ! command -v shfmt >/dev/null 2>&1; then
	SHFMT_VERSION=v3.8.0
	log "instalando shfmt ${SHFMT_VERSION}"
	curl -fsSL "https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_amd64" \
		-o /usr/local/bin/shfmt
	chmod +x /usr/local/bin/shfmt
fi

if ! command -v git-cliff >/dev/null 2>&1; then
	GIT_CLIFF_VERSION=2.6.1
	log "instalando git-cliff ${GIT_CLIFF_VERSION}"
	curl -fsSL \
		"https://github.com/orhun/git-cliff/releases/download/v${GIT_CLIFF_VERSION}/git-cliff-${GIT_CLIFF_VERSION}-x86_64-unknown-linux-gnu.tar.gz" |
		tar -xz -C /tmp
	install -m 0755 "/tmp/git-cliff-${GIT_CLIFF_VERSION}/git-cliff" /usr/local/bin/git-cliff
fi

# --- citools ---
log "rustup components (rustfmt, clippy)"
rustup component add rustfmt clippy >/dev/null 2>&1 || true

log "compilando citools (release)"
cd "${REPO_ROOT}/tools/citools"
cargo build --release --locked 2>/dev/null || cargo build --release
CITOOLS_BIN="${CARGO_TARGET_DIR}/release/citools"
export PATH="${CARGO_TARGET_DIR}/release:${PATH}"
install -m 0755 "${CITOOLS_BIN}" /usr/local/bin/citools 2>/dev/null || true

command -v citools >/dev/null
citools --version 2>/dev/null || true

# --- CodeQL bundle (cache no workspace) ---
CODEQL_HOME="${REPO_ROOT}/.codeql"
CODEQL_VERSION="${CODEQL_VERSION:-2.20.5}"
if [[ ! -x "${CODEQL_HOME}/codeql/codeql" ]]; then
	log "baixando CodeQL bundle ${CODEQL_VERSION}"
	mkdir -p "${CODEQL_HOME}"
	curl -fsSL \
		"https://github.com/github/codeql-action/releases/download/codeql-bundle-v${CODEQL_VERSION}/codeql-bundle-linux64.tar.gz" \
		-o /tmp/codeql-bundle-linux64.tar.gz
	tar -xzf /tmp/codeql-bundle-linux64.tar.gz -C "${CODEQL_HOME}"
fi
CODEQL_BIN="${CODEQL_HOME}/codeql/codeql"

# Env file — stages dinâmicos (citools run) rodam em sh novo sem herdar PATH do setup
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
if [[ ! -d "$JAVA_HOME" ]] && command -v java >/dev/null 2>&1; then
	JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
fi
cat >"${REPO_ROOT}/.citools-agent.env" <<EOF
export JAVA_HOME="${JAVA_HOME}"
export CODEQL_BIN="${CODEQL_BIN}"
export PATH="${CODEQL_HOME}/codeql:${SONAR_SCANNER_HOME}/bin:/usr/local/bin:/usr/local/cargo/bin:${CARGO_TARGET_DIR}/release:/usr/bin:\${PATH}"
EOF

log "agent pronto — citools + node + shellcheck + sonar-scanner"
