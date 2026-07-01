#!/usr/bin/env bash
# seed_jenkins_agent_meter_oss_job.sh — multibranch agent-meter OSS (T-365)
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
GROOVY_FILE="${GROOVY_FILE:-$REPO_ROOT/components/ssdnodes/jenkins/bootstrap-agent-meter-oss-job.groovy}"

log() { echo "[seed-agent-meter-oss] $*"; }

[[ -f "$GROOVY_FILE" ]] || { echo "❌ $GROOVY_FILE não encontrado" >&2; exit 2; }

for _ in $(seq 1 60); do
  if ssh "$REMOTE_HOST" "kubectl get pod jenkins-0 -n jenkins -o jsonpath='{.status.containerStatuses[?(@.name==\"jenkins\")].ready}'" 2>/dev/null | grep -q true; then
    break
  fi
  sleep 5
done

scp -q "$GROOVY_FILE" "$REMOTE_HOST:/tmp/bootstrap-agent-meter-oss-job.groovy"
ssh "$REMOTE_HOST" "kubectl cp /tmp/bootstrap-agent-meter-oss-job.groovy jenkins/jenkins-0:/tmp/bootstrap-agent-meter-oss-job.groovy -c jenkins"

log "Script Console..."
OUT=$(ssh "$REMOTE_HOST" "kubectl exec -n jenkins jenkins-0 -c jenkins -- bash -c '
JP=\$(cat /run/secrets/additional/chart-admin-password)
curl -sS -c /tmp/jc -u admin:\$JP http://127.0.0.1:8080/login >/dev/null
CRUMB=\$(curl -sS -b /tmp/jc -u admin:\$JP http://127.0.0.1:8080/crumbIssuer/api/json | sed -n \"s/.*\\\"crumb\\\":\\\"\\([^\\\"]*\\)\\\".*/\\1/p\")
GROOVY=\$(cat /tmp/bootstrap-agent-meter-oss-job.groovy)
curl -sS -b /tmp/jc -u admin:\$JP -H \"Jenkins-Crumb: \$CRUMB\" --data-urlencode \"script=\$GROOVY\" http://127.0.0.1:8080/scriptText
'")

echo "$OUT"
echo "$OUT" | grep -q 'multibranch agent-meter-oss OK' || exit 1
log "✓ https://jenkins.ssdnodes.dnor.io/job/agent-meter-oss/"
