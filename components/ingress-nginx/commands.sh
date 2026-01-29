#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")"

echo "🌐 Installing Ingress NGINX..."
kubectl apply -f "$dir/deploy.yaml"

echo "⏳ Waiting for Ingress NGINX..."
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=5m || true

# Ensure ConfigMap exists (safety check if postgres component isn't present)
if ! kubectl -n ingress-nginx get configmap tcp-services >/dev/null 2>&1; then
    echo "⚠️ 'tcp-services' ConfigMap missing. Creating empty one to silence controller warnings."
    kubectl -n ingress-nginx create configmap tcp-services
fi

echo "✅ Ingress NGINX configured."
