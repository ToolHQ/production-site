#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")"

echo "🌐 Installing Ingress NGINX (Declarative)..."
kubectl apply -f "$dir/deploy.yaml"

echo "⏳ Waiting for Ingress NGINX..."
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=5m || true

echo "✅ Ingress NGINX configured."
