#!/usr/bin/env bash
# validate_ssdnodes_ci.sh — smoke TLS + endpoints CI SSDNodes (T-341)
set -euo pipefail

SONAR_URL="${SONAR_URL:-https://sonar.ssdnodes.dnor.io}"
JENKINS_URL="${JENKINS_URL:-https://jenkins.ssdnodes.dnor.io}"
REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"

ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; FAIL=1; }

FAIL=0

echo "=== validate_ssdnodes_ci (T-341) ==="

if curl -fsSI --max-time 15 "$SONAR_URL/api/system/status" >/dev/null 2>&1; then
  ok "Sonar HTTPS + /api/system/status ($SONAR_URL)"
else
  bad "Sonar indisponível ($SONAR_URL) — DNS/deploy pendente?"
fi

if curl -fsSI --max-time 15 "$JENKINS_URL/login" >/dev/null 2>&1; then
  ok "Jenkins HTTPS + /login ($JENKINS_URL)"
else
  bad "Jenkins indisponível ($JENKINS_URL) — DNS/deploy pendente?"
fi

if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl get pods -n sonarqube -o wide 2>/dev/null | tail -n +2 | grep -q Running" 2>/dev/null; then
  ok "Pods sonarqube Running no cluster"
else
  bad "Namespace sonarqube sem pods Running (deploy não executado?)"
fi

if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl get pods -n jenkins -o wide 2>/dev/null | tail -n +2 | grep -q Running" 2>/dev/null; then
  ok "Pods jenkins Running no cluster"
else
  bad "Namespace jenkins sem pods Running (deploy não executado?)"
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "PASS validate_ssdnodes_ci"
  exit 0
fi

echo "FAIL validate_ssdnodes_ci (esperado antes do primeiro deploy remoto)"
exit 1
