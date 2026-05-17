#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$dir/../.." && pwd)"
helm_cmd="$repo_root/tools/helm_compat.sh"

echo "🚀 Deploying Kubecost with optimized resources..."

# Add repo if missing
"$helm_cmd" repo add cost-analyzer https://kubecost.github.io/cost-analyzer/ >/dev/null 2>&1 || true
"$helm_cmd" repo update >/dev/null 2>&1 || true

# Check if Coroot Prometheus server is running in the cluster to reuse it
HELM_ARGS=(
    "upgrade" "--install" "kubecost" "cost-analyzer/cost-analyzer"
    "--namespace" "kubecost" "--create-namespace"
    "--version" "1.108.1"
    "--values" "$dir/values.yaml"
)

if kubectl get svc coroot-prometheus-server -n coroot >/dev/null 2>&1; then
    echo "⚡ Detected existing Coroot Prometheus server in namespace 'coroot'!"
    echo "⚡ Unifying Prometheus stacks: Kubecost will reuse Coroot's Prometheus."
    HELM_ARGS+=(
        "--set" "global.prometheus.enabled=false"
        "--set" "global.prometheus.fqdn=http://coroot-prometheus-server.coroot.svc.cluster.local:80"
    )
else
    echo "ℹ️ No Coroot Prometheus server detected. Using bundled Prometheus stack."
fi

HELM_ARGS+=("--wait")

# Install/Upgrade
"$helm_cmd" "${HELM_ARGS[@]}"

# Grafana desabilitado via values.yaml (grafana.enabled: false)
# Se deployment legado ainda existir no cluster, escalar para 0
if kubectl get deployment -n kubecost kubecost-grafana >/dev/null 2>&1; then
    kubectl scale deployment -n kubecost kubecost-grafana --replicas=0
    echo "  - kubecost-grafana desabilitado (replicas=0) — legado"
fi

# Se mudamos para Prometheus externo, garantir que o prometheus-server legado do kubecost seja removido/escalado a 0
if kubectl get deployment -n kubecost kubecost-prometheus-server >/dev/null 2>&1; then
    if kubectl get svc coroot-prometheus-server -n coroot >/dev/null 2>&1; then
        echo "🧹 Cleaning up legacy bundled Kubecost Prometheus server..."
        kubectl scale deployment -n kubecost kubecost-prometheus-server --replicas=0 2>/dev/null || true
    fi
fi

echo "✅ Kubecost deployed."
