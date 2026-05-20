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
# Se deployment legado ainda existir no cluster, remover completamente
if kubectl get deployment -n kubecost kubecost-grafana >/dev/null 2>&1; then
    echo "🧹 Removing legacy Kubecost Grafana deployment, service and configs..."
    kubectl delete deployment -n kubecost kubecost-grafana --ignore-not-found=true
    kubectl delete service -n kubecost kubecost-grafana --ignore-not-found=true
    
    # Deletar todos os configmaps de dashboards e configuracoes legadas do Grafana
    # NOTA: nginx-conf NÃO deve ser deletado — é usado pelo nginx sidecar do cost-analyzer
    kubectl delete configmap -n kubecost \
      kubecost-grafana \
      kubecost-grafana-config-dashboards \
      attached-disk-metrics-dashboard \
      cluster-metrics-dashboard \
      cluster-utilization-dashboard \
      deployment-utilization-dashboard \
      grafana-dashboard-kubernetes-resource-efficiency \
      grafana-dashboard-networkcosts-metrics \
      grafana-dashboard-pod-utilization-multi-cluster \
      label-cost-dashboard \
      namespace-utilization-dashboard \
      node-utilization-dashboard \
      pod-utilization-dashboard \
      prom-benchmark-dashboard --ignore-not-found=true 2>/dev/null || true
fi

# Se mudamos para Prometheus externo, garantir que o prometheus-server legado do kubecost seja removido/escalado a 0
if kubectl get deployment -n kubecost kubecost-prometheus-server >/dev/null 2>&1; then
    if kubectl get svc coroot-prometheus-server -n coroot >/dev/null 2>&1; then
        echo "🧹 Cleaning up legacy bundled Kubecost Prometheus server..."
        kubectl scale deployment -n kubecost kubecost-prometheus-server --replicas=0 2>/dev/null || true
    fi
fi

echo "✅ Kubecost deployed."
