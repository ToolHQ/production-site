#!/usr/bin/env bash
# trigger_jenkins_deploy_smoke.sh — build deploy-apps DRY_RUN (T-348 smoke)
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
APP="${APP:-py-back-end}"
TARGET="${TARGET:-oci}"
DRY_RUN="${DRY_RUN:-true}"

ssh "$REMOTE_HOST" "kubectl exec -n jenkins jenkins-0 -c jenkins -- bash -s" <<REMOTE
set -euo pipefail
JP=\$(cat /run/secrets/additional/chart-admin-password)
curl -sS -c /tmp/jc -u "admin:\$JP" http://127.0.0.1:8080/login >/dev/null
CRUMB=\$(curl -sS -b /tmp/jc -u "admin:\$JP" http://127.0.0.1:8080/crumbIssuer/api/json | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')
CODE=\$(curl -sS -b /tmp/jc -u "admin:\$JP" -H "Jenkins-Crumb: \$CRUMB" -X POST \
  "http://127.0.0.1:8080/job/deploy-apps/buildWithParameters?APP=${APP}&TARGET=${TARGET}&DRY_RUN=${DRY_RUN}" \
  -o /dev/null -w '%{http_code}')
echo "deploy-apps build: HTTP \$CODE"
REMOTE

echo "→ https://jenkins.ssdnodes.dnor.io/job/deploy-apps/"
