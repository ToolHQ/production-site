#!/usr/bin/env bash
set -e

# commands.sh for Observability Component
# Executed by deploy_components.sh

echo "🔭 Setting up Observability Stack..."

# 1. Metrics Server Check
echo " [1] Checking Metrics Server..."
if kubectl top nodes &> /dev/null; then
    echo "    ✅ Metrics Server is healthy."
else
    echo "    ⚠️  Metrics Server seems missing or broken. Deploying..."
    # Standard High-Availability Metrics Server
    kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
    # Patch for insecure TLS (common in self-hosted/testing)
    kubectl patch -n kube-system deployment metrics-server --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
fi

# 2. Pixie CLI
echo " [2] Check Pixie CLI..."
if command -v px &> /dev/null; then
    echo "    ✅ 'px' CLI found."
else
    echo "    📥 Installing Pixie CLI (Direct Binary for ARM64)..."
    
    # 1. Fetch latest version tag from README (most reliable source for Pixie)
    LATEST_VERSION=$(curl -fsSL https://raw.githubusercontent.com/pixie-io/pixie/main/README.md | grep -oE 'v([0-9]+\.[0-9]+\.[0-9]+)<!--cli-latest-release-->' | head -n 1 | sed 's/<!--.*//')
    
    # Fallback if detection fails
    if [[ -z "$LATEST_VERSION" ]]; then
        echo "    ⚠️  Could not detect latest version, falling back to v0.8.10"
        LATEST_VERSION="v0.8.10"
    fi
    
    echo "    ℹ️  Target Version: $LATEST_VERSION"
    
    # 2. Construct URL (Note the URL encoding for the tag in the path: release%2Fcli%2Fv...)
    # Pattern: https://github.com/pixie-io/pixie/releases/download/release%2Fcli%2Fv0.8.10/cli_linux_arm64
    DOWNLOAD_URL="https://github.com/pixie-io/pixie/releases/download/release%2Fcli%2F${LATEST_VERSION}/cli_linux_arm64"
    
    curl -L -o px "$DOWNLOAD_URL"
    chmod +x px
    sudo mv px /usr/local/bin/px || echo "    ⚠️  Failed to move to /usr/local/bin, trying local bin..." && mkdir -p ~/bin && mv px ~/bin/px && export PATH=$PATH:~/bin
    
    if command -v px &> /dev/null; then
        echo "    ✅ 'px' CLI installed successfully."
        echo "    ℹ️  To finalize setup, run locally: 'px deploy'"
    else
        echo "    ❌ 'px' binary download failed or not in PATH."
    fi
fi

echo ""
# 3. Deploy DeepFlow (eBPF Observability)
echo " [3] Deploying DeepFlow..."
if helm list -n deepflow | grep -q deepflow; then
    echo "    ✅ DeepFlow already deployed."
else
    echo "    📥 Installing DeepFlow via Helm..."
    
    # Create namespace
    kubectl create namespace deepflow --dry-run=client -o yaml | kubectl apply -f -
    
    # Add Helm repo if not exists
    if ! helm repo list | grep -q deepflow; then
        helm repo add deepflow https://deepflowio.github.io/deepflow
        helm repo update
    fi
    
    # Install DeepFlow with custom values
    helm install deepflow deepflow/deepflow \
        -n deepflow \
        -f deepflow_values.yaml \
        --wait --timeout 10m
    
    # Apply Ingress
    if [ -f "manifests/deepflow-ingress.yaml" ]; then
        kubectl apply -f manifests/deepflow-ingress.yaml
    fi
    
    echo "    ✅ DeepFlow deployed successfully."
    echo "    🌐 Access UI at: https://deepflow.dnor.io"
fi

echo ""
echo "✅ Observability Setup (DeepFlow + Metrics) finished."
