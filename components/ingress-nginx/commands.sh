#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")"

echo "🌐 Installing Ingress NGINX..."
kubectl apply -f "$dir/deploy.yaml"

echo "⏳ Waiting for Ingress NGINX..."
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=5m || true

# --- TCP Services (Postgres) ---
echo "🔧 Configuring TCP Services (Postgres 5432)..."

# Ensure ConfigMap exists
if ! kubectl -n ingress-nginx get configmap tcp-services >/dev/null 2>&1; then
    kubectl -n ingress-nginx create configmap tcp-services
fi

# Patch Deployment for TCP Port 5432
if ! kubectl -n ingress-nginx get deploy ingress-nginx-controller -o yaml | grep -q 'containerPort: 5432'; then
    kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type='json' -p='[
        {"op":"add","path":"/spec/template/spec/containers/0/ports/-","value":{"name":"postgres","containerPort":5432,"protocol":"TCP"}}
    ]'
    echo "✅ Added 5432 containerPort"
else
    echo "✅ 5432 containerPort already exists"
fi

# Patch Service for TCP Port 5432
if ! kubectl -n ingress-nginx get svc ingress-nginx-controller -o yaml | grep -q 'name: postgres'; then
    kubectl -n ingress-nginx patch service ingress-nginx-controller --type='json' -p='[
        {"op":"add","path":"/spec/ports/-","value":{"name":"postgres","port":5432,"targetPort":5432,"protocol":"TCP"}}
    ]'
    echo "✅ Added 5432 Service Port"
else
    echo "✅ 5432 Service Port already exists"
fi

# Enable TCP Services ConfigMap Arg
if ! kubectl -n ingress-nginx get deploy ingress-nginx-controller -o yaml | grep -q 'tcp-services-configmap'; then
    kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type='json' -p='[
        {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--tcp-services-configmap=ingress-nginx/tcp-services"}
    ]'
    echo "✅ Added --tcp-services-configmap arg"
else
    echo "✅ --tcp-services-configmap arg already exists"
fi

echo "✅ Ingress NGINX configured."
