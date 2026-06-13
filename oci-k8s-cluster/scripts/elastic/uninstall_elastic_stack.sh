#!/usr/bin/env bash
# uninstall_elastic_stack.sh — remove Elastic Stack (ECK) from OCI cluster
# Retired: stack too heavy for 1 vCPU nodes. Future logs → Vector + Parquet on MinIO.
set -euo pipefail

NS="elastic-system"
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "-" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  OPERATOR_MANIFEST="$REPO_ROOT/components/_archived/elastic-stack/operator.yaml"
else
  OPERATOR_MANIFEST=""
fi

log() { echo "[elastic-uninstall] $*"; }

patch_finalizers() {
  local kind="$1" name="$2"
  kubectl patch "$kind" "$name" -n "$NS" \
    -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
}

delete_cr() {
  local res="$1"
  if kubectl get "$res" -n "$NS" >/dev/null 2>&1; then
    log "Deleting $res ..."
    kubectl delete "$res" -n "$NS" --timeout=45s --ignore-not-found 2>/dev/null \
      || patch_finalizers "${res%%/*}" "${res#*/}"
    kubectl delete "$res" -n "$NS" --force --grace-period=0 --ignore-not-found 2>/dev/null || true
  fi
}

log "Starting Elastic Stack removal (namespace: $NS)"

# Ingress + TLS-only resources
kubectl delete ingress elastic-stack-ingress -n "$NS" --ignore-not-found 2>/dev/null || true
kubectl delete certificate elk-tls -n "$NS" --ignore-not-found 2>/dev/null || true

# ECK custom resources (order: dependents first)
for res in \
  beat/oci-filebeat \
  logstash/oci-logstash \
  kibana/oci-logs \
  elasticsearch/oci-logs; do
  delete_cr "$res"
done

# Leftover workloads not owned by a CR
kubectl delete deployment,statefulset,daemonset -n "$NS" --all --ignore-not-found 2>/dev/null || true
kubectl delete pods -n "$NS" --all --force --grace-period=0 2>/dev/null || true

# PVCs (Longhorn volumes)
kubectl get pvc -n "$NS" -o name 2>/dev/null | while read -r pvc; do
  log "Deleting $pvc"
  kubectl patch "$pvc" -n "$NS" -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
  kubectl delete "$pvc" -n "$NS" --force --grace-period=0 2>/dev/null || true
done

# Orphan Longhorn volumes for elastic-system PVCs
for vol in $(kubectl get volumes.longhorn.io -n longhorn-system -o json 2>/dev/null \
  | jq -r '.items[] | select(.status.kubernetesStatus.namespace=="elastic-system") | .metadata.name'); do
  log "Deleting Longhorn volume $vol"
  kubectl delete volume.longhorn.io "$vol" -n longhorn-system --ignore-not-found 2>/dev/null || true
done

# ECK operator (local manifest preferred; fallback to upstream)
if [[ -f "$OPERATOR_MANIFEST" ]]; then
  log "Removing ECK operator from archived manifest..."
  kubectl delete -f "$OPERATOR_MANIFEST" --ignore-not-found 2>/dev/null || true
else
  log "Removing ECK operator from upstream 2.10.0..."
  kubectl delete -f "https://download.elastic.co/downloads/eck/2.10.0/operator.yaml" --ignore-not-found 2>/dev/null || true
fi

kubectl delete validatingwebhookconfiguration elastic-webhook.k8s.elastic.co --ignore-not-found 2>/dev/null || true

# CRDs
mapfile -t CRDS < <(kubectl get crd -o name 2>/dev/null | grep -E 'elastic\.co|k8s\.elastic\.co' || true)
if [[ ${#CRDS[@]} -gt 0 ]]; then
  log "Removing ECK CRDs (${#CRDS[@]})..."
  kubectl delete "${CRDS[@]}" --ignore-not-found 2>/dev/null || true
fi

# Namespace last
if kubectl get namespace "$NS" >/dev/null 2>&1; then
  kubectl patch namespace "$NS" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  kubectl delete namespace "$NS" --timeout=120s --ignore-not-found 2>/dev/null || true
fi

log "Done. Remaining elastic resources:"
kubectl get all,elasticsearch,kibana,logstash,beat -A 2>/dev/null | grep -i elastic || echo "  (none)"
