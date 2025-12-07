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

# 2. ECK Operator (Elastic Cloud on Kubernetes)
echo " [2] Deploying ECK Operator..."
if kubectl get ns elastic-system &> /dev/null; then
    echo "    ℹ️  elastic-system namespace exists."
    if kubectl get pod -n elastic-system -l control-plane=elastic-operator | grep Running &> /dev/null; then
        echo "    ✅ ECK Operator is running."
    else
        echo "    🔄 Updating ECK Operator..."
        kubectl create -f https://download.elastic.co/downloads/eck/2.10.0/crds.yaml || true
        kubectl apply -f https://download.elastic.co/downloads/eck/2.10.0/operator.yaml
    fi
else
    echo "    📥 Installing ECK Operator (v2.10.0)..."
    kubectl create -f https://download.elastic.co/downloads/eck/2.10.0/crds.yaml
    kubectl apply -f https://download.elastic.co/downloads/eck/2.10.0/operator.yaml
fi

# 3. Apply Local Manifests (recursively if needed, but structure is flattened mostly or in manifests/)
echo " [3] Applying ELK Manifests..."
# Check if manifests directory exists relative to this script
if [ -d "manifests" ]; then
    kubectl apply -f manifests/
else
    # Fallback if flat structure
    kubectl apply -f .
fi

# 4. Pixie CLI
echo " [4] Check Pixie CLI..."
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
echo "✅ Observability Setup (ECK + Manifests) finished."
