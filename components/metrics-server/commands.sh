#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")"

echo "📊 Installing Metrics Server..."
# Delete existing to prevent patch conflicts/duplicates
kubectl -n kube-system delete deploy metrics-server --ignore-not-found
kubectl apply -f "$dir/components.yaml"

# Patch for insecure TLS (required for most local/self-signed setups) and port 4443
echo "🔧 Patching Metrics Server args and ports..."
kubectl -n kube-system patch deployment metrics-server --type=json -p='[{
  "op":"replace","path":"/spec/template/spec/containers/0/ports",
  "value":[{"containerPort":4443,"name":"https","protocol":"TCP"}]
},{
  "op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":4443
},{
  "op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":4443
},{
  "op":"replace","path":"/spec/template/spec/containers/0/args",
  "value":[
    "--cert-dir=/tmp",
    "--secure-port=4443",
    "--kubelet-insecure-tls",
    "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
    "--metric-resolution=15s"
  ]
}]'

echo "⏳ Waiting for Metrics Server..."
kubectl -n kube-system rollout restart deploy metrics-server
kubectl -n kube-system rollout status deploy metrics-server --timeout=120s

echo "✅ Metrics Server installed."
