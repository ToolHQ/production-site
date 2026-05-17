#!/usr/bin/env bash
# Dispara jobs de extract respeitando RPM (via LLM_MAX_RPM no CronJob/CLI).
# Uso: ROUNDS=5 ./scripts/drain-extract-backlog.sh

set -euo pipefail

NAMESPACE="${AI_RADAR_NAMESPACE:-ai-radar}"
ROUNDS="${ROUNDS:-5}"
WAIT_SEC="${WAIT_SEC:-1200}"

export KUBECONFIG="${KUBECONFIG:-$HOME/production-site/oci-k8s-cluster/kubeconfig_tunnel.yaml}"

log() { printf '→ %s\n' "$*"; }

pending() {
  kubectl -n "$NAMESPACE" exec -n postgres postgres-0 -- \
    env PGPASSWORD="$(kubectl get secret postgres-secret -n postgres -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)" \
    psql -U "$(kubectl get secret postgres-secret -n postgres -o jsonpath='{.data.POSTGRES_USER}' | base64 -d)" \
    -d postgres -tAc "SELECT count(*) FROM ai_radar.raw_items WHERE status='pending';" 2>/dev/null \
    || echo "?"
}

for ((r = 1; r <= ROUNDS; r++)); do
  n="$(pending)"
  log "round $r/$ROUNDS — pending=$n"
  if [[ "$n" == "0" ]]; then
    log "fila vazia"
    break
  fi
  job="drain-extract-${r}-$(date +%s)"
  kubectl -n "$NAMESPACE" create job --from=cronjob/ai-radar-extract "$job"
  kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$job" --timeout="${WAIT_SEC}s" || true
  kubectl -n "$NAMESPACE" logs "job/$job" --tail=5 || true
  sleep 5
done

log "final pending=$(pending)"
