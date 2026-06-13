#!/usr/bin/env bash
# validate_ai_radar_trends.sh — T-363 harness (CronJob + DB rows)
set -euo pipefail

NAMESPACE="${AI_RADAR_NS:-ai-radar}"
JOB_NAME="${TRENDS_JOB_NAME:-ai-radar-trends-collect-manual}"
TIMEOUT="${TRENDS_JOB_TIMEOUT:-600}"

ok() { echo "✓ $*"; }
bad() { echo "✗ $*"; FAIL=1; }

FAIL=0
echo "=== validate_ai_radar_trends (T-363) ==="

if ! kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
	bad "namespace $NAMESPACE ausente"
	echo "FAIL validate_ai_radar_trends"
	exit 1
fi

if ! kubectl get cronjob ai-radar-trends-collect -n "$NAMESPACE" >/dev/null 2>&1; then
	bad "CronJob ai-radar-trends-collect ausente"
	echo "FAIL validate_ai_radar_trends"
	exit 1
fi
ok "CronJob ai-radar-trends-collect presente"

kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1
kubectl create job "$JOB_NAME" --from=cronjob/ai-radar-trends-collect -n "$NAMESPACE" >/dev/null

if kubectl wait --for=condition=complete "job/$JOB_NAME" -n "$NAMESPACE" --timeout="${TIMEOUT}s" 2>/dev/null; then
	ok "Job manual Completed"
else
	bad "Job manual não completou em ${TIMEOUT}s"
	kubectl logs "job/$JOB_NAME" -n "$NAMESPACE" --tail=40 2>&1 || true
fi

rows="$(kubectl exec -n postgres postgres-0 -- env PGPASSWORD="$(kubectl get secret postgres-secret -n postgres -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)" \
	psql -U "$(kubectl get secret postgres-secret -n postgres -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)" -d postgres -tAc \
	"SELECT count(*) FROM ai_radar.trend_signals WHERE collected_at > now() - interval '2 hours';" 2>/dev/null | tr -d '[:space:]' || echo "0")"

if [[ "${rows:-0}" -ge 1 ]]; then
	ok "trend_signals rows recentes ($rows)"
else
	bad "nenhuma row em trend_signals (últimas 2h)"
fi

kubectl delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found >/dev/null 2>&1

if [[ "${FAIL:-0}" -eq 0 ]]; then
	echo "PASS validate_ai_radar_trends"
else
	echo "FAIL validate_ai_radar_trends"
	exit 1
fi
