#!/usr/bin/env bash
set -e

echo "💰 Setting up Kubecost (FinOps)..."

# 1. Install Helm if missing
if ! command -v helm &> /dev/null; then
    echo "    📥 Installing Helm (Remote)..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
fi

# 2. Add Kubecost Repo
echo "    ➕ Adding Kubecost Helm Repo..."
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm repo update

# 3. Create Namespace
kubectl create ns kubecost --dry-run=client -o yaml | kubectl apply -f -

# 4. Install/Upgrade Kubecost
echo "    🚀 Deploying Kubecost (ARM64 Optimized)..."
# We use a custom token or email. For free tier locally, we can use a placeholder
# but the UI might nag.
export KUBECOST_TOKEN="c2727142-2b6d-4952-b912-f0469b82142f" # Public example token often used in docs, or we ask user later.

helm upgrade --install kubecost kubecost/cost-analyzer \
    --namespace kubecost \
    --version 1.108.1 \
    --set kubecostToken="$KUBECOST_TOKEN" \
    --set global.grafana.enabled=false \
    --set global.grafana.proxy=false \
    --set persistentVolume.size="2Gi" \
    --set prometheus.server.persistentVolume.size="2Gi" \
    --set prometheus.server.resources.requests.memory=256Mi \
    --set prometheus.server.resources.requests.cpu=100m \
    --set cost-analyzer.resources.requests.memory=256Mi \
    --set cost-analyzer.resources.requests.cpu=100m \
    --set networkCosts.enabled=false \
    --set serviceMonitor.enabled=false \
    --set prometheus.kube-state-metrics.disabled=false \
    --set ingress.enabled=false 

# 5. Apply Ingress
echo "    🌐 Configuring Ingress..."
if [ -d "manifests" ]; then
    kubectl apply -f manifests/
else
    # Fallback if flat
    kubectl apply -f .
fi

echo "✅ Kubecost deployment triggered."
echo "    ⏳ It may take a few minutes for pods to be Ready."
