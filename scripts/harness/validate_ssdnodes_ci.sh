#!/usr/bin/env bash
# validate_ssdnodes_ci.sh — smoke TLS + endpoints + IaC drift CI SSDNodes (T-341 / T-343)
set -euo pipefail

SONAR_URL="${SONAR_URL:-https://sonar.ssdnodes.dnor.io}"
JENKINS_URL="${JENKINS_URL:-https://jenkins.ssdnodes.dnor.io}"
REMOTE_HOST="${REMOTE_HOST:-ssdnodes-6a12f10c9ef11}"

# Pins alinhados a components/ssdnodes/*-values.yaml (T-342 / T-343)
EXPECTED_SONAR_VERSION="${EXPECTED_SONAR_VERSION:-26.6.0.123539}"
EXPECTED_JENKINS_IMAGE_TAG="${EXPECTED_JENKINS_IMAGE_TAG:-2.567-slim-jdk25}"

ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; FAIL=1; }

FAIL=0

echo "=== validate_ssdnodes_ci (T-341 / T-343) ==="

# ─── Sonar ───────────────────────────────────────────────────────────────────
if sonar_json=$(curl -fsS --max-time 15 "$SONAR_URL/api/system/status" 2>/dev/null); then
  ok "Sonar HTTPS + /api/system/status ($SONAR_URL)"
  sonar_ver=$(echo "$sonar_json" | python3 -c "import sys,json; print(json.load(sys.stdin).get('version',''))" 2>/dev/null || true)
  if [[ "$sonar_ver" == "$EXPECTED_SONAR_VERSION" ]]; then
    ok "Sonar version IaC ($sonar_ver)"
  else
    bad "Sonar version drift: runtime=$sonar_ver expected=$EXPECTED_SONAR_VERSION"
  fi
else
  bad "Sonar indisponível ($SONAR_URL) — DNS/deploy pendente?"
fi

# ─── Jenkins TLS + reverse proxy smoke ───────────────────────────────────────
jenkins_headers=$(curl -fsSI --max-time 15 "$JENKINS_URL/login" 2>/dev/null || true)
if [[ -n "$jenkins_headers" ]]; then
  ok "Jenkins HTTPS + /login ($JENKINS_URL)"
  if echo "$jenkins_headers" | tr -d '\r' | grep -qiE '^Location:.*(:8080|:50000)'; then
    bad "Jenkins redirect expõe porta interna (reverse proxy quebrado?)"
  else
    ok "Jenkins redirects sem porta interna (:8080/:50000)"
  fi
  if echo "$jenkins_headers" | tr -d '\r' | grep -qiE '^content-security-policy(:|-report-only:)'; then
    ok "Jenkins CSP header presente (enforce ou report-only)"
  else
    bad "Jenkins CSP header ausente (T-343 initScripts)"
  fi
else
  bad "Jenkins indisponível ($JENKINS_URL) — DNS/deploy pendente?"
fi

# ─── Cluster pods + imagem IaC ───────────────────────────────────────────────
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

if jenkins_img=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl get pod jenkins-0 -n jenkins -o jsonpath='{.spec.containers[?(@.name==\"jenkins\")].image}'" 2>/dev/null); then
  if echo "$jenkins_img" | grep -q "$EXPECTED_JENKINS_IMAGE_TAG"; then
    ok "Jenkins image IaC ($EXPECTED_JENKINS_IMAGE_TAG)"
  else
    bad "Jenkins image drift: $jenkins_img (expected tag *$EXPECTED_JENKINS_IMAGE_TAG*)"
  fi
fi

# ─── deploy-apps job (T-348) ─────────────────────────────────────────────────
if ssh -o ConnectTimeout=10 -o BatchMode=yes "$REMOTE_HOST" \
  "kubectl exec -n jenkins jenkins-0 -c jenkins -- test -f /var/jenkins_home/jobs/deploy-apps/config.xml" 2>/dev/null; then
  ok "Jenkins job deploy-apps presente"
else
  bad "Jenkins job deploy-apps ausente — rode seed_jenkins_deploy_job.sh"
fi

if [[ "$FAIL" -eq 0 ]]; then
  echo "PASS validate_ssdnodes_ci"
  exit 0
fi

echo "FAIL validate_ssdnodes_ci"
exit 1
