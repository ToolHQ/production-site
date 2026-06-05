#!/usr/bin/env bash
# sonar-scan.sh — wrapper Sonar scanner para citools stage (T-341 fase 2)
set -euo pipefail

SONAR_HOST_URL="${SONAR_HOST_URL:-https://sonar.ssdnodes.dnor.io}"
SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-production-site}"

[[ -n "${SONAR_TOKEN:-}" ]] || {
  echo "SONAR_TOKEN não definido — skip sonar-scan" >&2
  exit 0
}

if ! command -v sonar-scanner >/dev/null 2>&1; then
  echo "sonar-scanner não instalado no agent — skip (instale via Jenkinsfile ou imagem)" >&2
  exit 0
fi

if [[ ! -f sonar-project.properties ]]; then
  echo "sonar-project.properties ausente — skip sonar-scan até configurar escopo do monorepo" >&2
  exit 0
fi

sonar-scanner \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.host.url="$SONAR_HOST_URL" \
  -Dsonar.login="$SONAR_TOKEN"
