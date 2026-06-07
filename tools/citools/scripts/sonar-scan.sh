#!/usr/bin/env bash
# sonar-scan.sh — wrapper Sonar scanner para citools stage (T-341 fase 2)

SONAR_HOST_URL="${SONAR_HOST_URL:-https://sonar.ssdnodes.dnor.io}"
SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-production-site}"

# shellcheck source=/dev/null
[[ -f .citools-agent.env ]] && source .citools-agent.env

if [[ -n "${JAVA_HOME:-}" && ! -x "${JAVA_HOME}/bin/java" ]]; then
	unset JAVA_HOME
fi

if ! command -v java >/dev/null 2>&1; then
	echo "[sonar-scan] java ausente — instalando openjdk-17-jre-headless" >&2
	export DEBIAN_FRONTEND=noninteractive
	apt-get update -qq
	apt-get install -y -qq --no-install-recommends openjdk-17-jre-headless ca-certificates
fi

JAVA_BIN="$(command -v java)"
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$JAVA_BIN")")")"
export JAVA_HOME
export PATH="${JAVA_HOME}/bin:${PATH}"
echo "[sonar-scan] java: ${JAVA_BIN} (JAVA_HOME=${JAVA_HOME})" >&2

set -euo pipefail

[[ -n "${SONAR_TOKEN:-}" ]] || {
	echo "SONAR_TOKEN não definido — skip sonar-scan" >&2
	exit 0
}

if ! command -v sonar-scanner >/dev/null 2>&1; then
	echo "sonar-scanner não instalado no agent — skip" >&2
	exit 0
fi

if [[ ! -f sonar-project.properties ]]; then
	echo "sonar-project.properties ausente — skip sonar-scan" >&2
	exit 0
fi

sonar-scanner \
	-Dsonar.scanner.skipJreProvisioning=true \
	-Dsonar.scanner.javaExePath="${JAVA_BIN}" \
	-Dsonar.projectKey="$SONAR_PROJECT_KEY" \
	-Dsonar.host.url="$SONAR_HOST_URL" \
	-Dsonar.token="$SONAR_TOKEN"
