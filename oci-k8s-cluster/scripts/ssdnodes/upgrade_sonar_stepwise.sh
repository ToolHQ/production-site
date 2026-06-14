#!/usr/bin/env bash
# upgrade_sonar_stepwise.sh — Sonar 10.x legado → 26.x (T-342)
#
# Modos:
#   --fresh (default se DB em 10.x quebrado) — drop DB + PVC, instala 26.6 limpo
#   --stepwise — 24.12 → 25.12 → 26.6 (preserva histórico; lento)
#
# Uso:
#   bash oci-k8s-cluster/scripts/ssdnodes/upgrade_sonar_stepwise.sh --fresh
#   bash oci-k8s-cluster/scripts/ssdnodes/upgrade_sonar_stepwise.sh --stepwise
#
# Pré-requisito: upload_manifests (deploy_ssdnodes_components) em /tmp/ssdnodes-components/

set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"
SONARQUBE_HELM_CHART_VERSION="${SONARQUBE_HELM_CHART_VERSION:-2026.3.1}"
TARGET_BUILD="${TARGET_BUILD:-26.6.0.123539}"
MODE="${1:---fresh}"

log() { echo "[upgrade-sonar] $*"; }

case "$MODE" in
--fresh | --stepwise) ;;
*)
  echo "Uso: $0 [--fresh|--stepwise]" >&2
  exit 1
  ;;
esac

ssh "$REMOTE_HOST" bash << REMOTE
set -euo pipefail
SONARQUBE_HELM_CHART_VERSION="${SONARQUBE_HELM_CHART_VERSION}"
TARGET_BUILD="${TARGET_BUILD}"
MODE="${MODE}"

helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube 2>/dev/null || true
helm repo update sonarqube

sonar_status() {
  kubectl exec -n sonarqube sonarqube-sonarqube-0 -c sonarqube -- \
    curl -fsS http://127.0.0.1:9000/api/system/status 2>/dev/null || echo '{"status":"DOWN"}'
}

helm_target() {
  local build="\$1"
  cat > /tmp/sonarqube-target.yaml << YAML
community:
  enabled: true
  buildNumber: "\${build}"
image:
  tag: \${build}-community
YAML
  helm upgrade --install sonarqube sonarqube/sonarqube \
    --namespace sonarqube \
    --version "\${SONARQUBE_HELM_CHART_VERSION}" \
    -f /tmp/ssdnodes-components/sonarqube-values.yaml \
    -f /tmp/sonarqube-target.yaml \
    --wait --timeout 35m
  kubectl delete pod sonarqube-sonarqube-0 -n sonarqube --wait=false 2>/dev/null || true
  kubectl rollout status statefulset/sonarqube-sonarqube -n sonarqube --timeout=35m
}

wait_up() {
  for i in \$(seq 1 80); do
    st=\$(sonar_status | grep -o '"status":"[^"]*"' | head -1 || true)
    echo "  [\$i/80] \$st"
    echo "\$st" | grep -q '"status":"UP"' && return 0
    sleep 15
  done
  sonar_status
  return 1
}

if [[ "\$MODE" == "--fresh" ]]; then
  echo "[upgrade-sonar] Fresh install Sonar Community Build \${TARGET_BUILD}"
  kubectl scale statefulset sonarqube-sonarqube -n sonarqube --replicas=0 2>/dev/null || true
  kubectl wait --for=delete pod/sonarqube-sonarqube-0 -n sonarqube --timeout=180s 2>/dev/null || true
  kubectl delete pvc sonarqube-sonarqube -n sonarqube --wait=true 2>/dev/null || true
  pg_admin="\$(kubectl get secret sonarqube-db-credentials -n sonarqube-db -o jsonpath='{.data.postgres-password}' | base64 -d)"
  kubectl exec -n sonarqube-db sonarqube-db-postgresql-0 -- env PGPASSWORD="\${pg_admin}" \
    psql -U postgres -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS sonar;" \
    -c "CREATE DATABASE sonar OWNER sonar;"
  helm_target "\${TARGET_BUILD}"
  wait_up
else
  echo "[upgrade-sonar] Stepwise 24.12 → 25.12 → \${TARGET_BUILD}"
  for step in 24.12.0.100206 25.12.0.117093 "\${TARGET_BUILD}"; do
    echo "[upgrade-sonar] === \$step ==="
    helm_target "\$step"
    wait_up
  done
fi
sonar_status
REMOTE

log "✓ Sonar em \${TARGET_BUILD}-community"
