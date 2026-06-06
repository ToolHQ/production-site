#!/usr/bin/env bash
# upgrade_jenkins_pipeline_ux.sh — helm upgrade plugins Blue Ocean + Stage View (T-349)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
JENKINS_URL="${JENKINS_URL:-https://jenkins.ssdnodes.dnor.io}"

log() { echo "[upgrade-jenkins-ux] $*"; }

log "Helm upgrade jenkins (blueocean + pipeline-stage-view + pipeline-graph-view)..."
scp -q "$REPO_ROOT/components/ssdnodes/jenkins-values.yaml" "$REMOTE_HOST:/tmp/ssdnodes-components/jenkins-values.yaml"
ssh "$REMOTE_HOST" bash <<REMOTE
set -euo pipefail
JENKINS_HELM_CHART_VERSION="${JENKINS_HELM_CHART_VERSION:-5.9.22}"
helm repo add jenkins https://charts.jenkins.io 2>/dev/null || true
helm repo update
helm upgrade --install jenkins jenkins/jenkins \
  --namespace jenkins \
  --version "\${JENKINS_HELM_CHART_VERSION}" \
  --values /tmp/ssdnodes-components/jenkins-values.yaml \
  --wait --timeout 25m
kubectl rollout status statefulset/jenkins -n jenkins --timeout=900s
REMOTE

for _ in $(seq 1 48); do
  curl -fsSI --max-time 10 "${JENKINS_URL}/login" >/dev/null 2>&1 && break
  sleep 5
done

log "Aguardando plugins (primeiro boot pós-install pode levar 2–5 min)..."
for _ in $(seq 1 36); do
  if ssh "$REMOTE_HOST" "kubectl exec -n jenkins jenkins-0 -c jenkins -- test -d /var/jenkins_home/plugins/blueocean" 2>/dev/null; then
    log "✓ blueocean plugin presente"
    break
  fi
  sleep 10
done

bash "$REPO_ROOT/scripts/harness/validate_ssdnodes_ci.sh"
log "✓ ${JENKINS_URL}/blue/"
