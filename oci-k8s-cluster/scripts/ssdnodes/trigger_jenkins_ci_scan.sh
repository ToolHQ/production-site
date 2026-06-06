#!/usr/bin/env bash
# trigger_jenkins_ci_scan.sh — força scan multibranch production-site (T-345)
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
JOB_NAME="${JENKINS_JOB_NAME:-production-site}"

ssh "$REMOTE_HOST" "kubectl exec -n jenkins jenkins-0 -c jenkins -- bash -s" <<REMOTE
set -euo pipefail
JP=\$(cat /run/secrets/additional/chart-admin-password)
curl -sS -c /tmp/jc -u "admin:\$JP" http://127.0.0.1:8080/login >/dev/null
CRUMB=\$(curl -sS -b /tmp/jc -u "admin:\$JP" http://127.0.0.1:8080/crumbIssuer/api/json | sed -n 's/.*"crumb":"\([^"]*\)".*/\1/p')
CODE=\$(curl -sS -b /tmp/jc -u "admin:\$JP" -H "Jenkins-Crumb: \$CRUMB" -X POST \
  "http://127.0.0.1:8080/job/${JOB_NAME}/build?delay=0sec" -o /dev/null -w '%{http_code}')
echo "multibranch scan: HTTP \$CODE"
REMOTE

echo "→ https://jenkins.ssdnodes.dnor.io/job/${JOB_NAME}/"
