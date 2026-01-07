#!/bin/bash
set -u

echo "🔥 Initiating Hard Reset of Elastic Stack Resources..."
NS="elastic-system"

resources=(
  "elasticsearch/oci-logs"
  "kibana/oci-logs"
  "logstash/oci-logstash"
  "beat/oci-filebeat"
)

for res in "${resources[@]}"; do
  echo "Checking $res..."
  if kubectl get "$res" -n "$NS" >/dev/null 2>&1; then
     echo "  ⚠️  Deleting $res..."
     # Attempt standard delete
     kubectl delete "$res" -n "$NS" --timeout=10s --wait=false 2>/dev/null
     
     # Patch finalizers to ensure it dies
     echo "  💉 Patching finalizers for $res..."
     kubectl patch "$res" -n "$NS" -p '{"metadata":{"finalizers":[]}}' --type=merge >/dev/null 2>&1 || true
     
     # Force delete
     kubectl delete "$res" -n "$NS" --force --grace-period=0 >/dev/null 2>&1 || true
     echo "  ✅ Deleted."
  else
     echo "  - Not found (Clean)."
  fi
done

echo "🧹 Cleaning orphaned pods in $NS..."
kubectl delete pods -n "$NS" -l common.k8s.elastic.co/type=elasticsearch --force --grace-period=0 2>/dev/null || true
kubectl delete pods -n "$NS" -l common.k8s.elastic.co/type=logstash --force --grace-period=0 2>/dev/null || true
kubectl delete pods -n "$NS" -l common.k8s.elastic.co/type=kibana --force --grace-period=0 2>/dev/null || true

echo "✨ Hard Reset Complete. Ready for fresh deployment."
