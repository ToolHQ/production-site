#!/bin/bash
set -euo pipefail

# PostgreSQL Deployment Script
# Tested in 2024-03-24
# Updated: 2025-11-08 - Added Longhorn support and improved error handling
# Reference: https://www.digitalocean.com/community/tutorials/how-to-deploy-postgres-to-kubernetes-cluster

echo "🐘 Starting PostgreSQL deployment..."

# Build and push Docker image
echo "📦 Building PostgreSQL image..."
if [ -f ./build.sh ]; then
    source ./build.sh
else
    echo "⚠️  build.sh not found, skipping image build"
fi

# Verify Longhorn storage class is available
echo "🔍 Verifying Longhorn storage class..."
if ! kubectl get storageclass longhorn >/dev/null 2>&1; then
    echo "⚠️  Warning: Longhorn storage class not found. The deployment may fail."
    echo "   Available storage classes:"
    kubectl get storageclass
    read -p "   Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Deployment cancelled."
        exit 1
    fi
fi

# Apply Kubernetes resources
echo "🚀 Applying PostgreSQL resources..."
kubectl apply -f postgres-resources.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for PostgreSQL deployment to be ready..."
if kubectl -n postgres rollout status deployment/postgres-deployment --timeout=5m; then
    echo "✅ PostgreSQL deployment successful!"
    
    # Display deployment info
    echo ""
    echo "📊 Deployment Status:"
    kubectl -n postgres get deployment,pod,svc,pvc -o wide
    
    echo ""
    echo "💡 Useful commands:"
    echo "   - Port forward: kubectl port-forward --namespace=postgres deployment/postgres-deployment 54322:5432"
    echo "   - View logs: kubectl -n postgres logs -l app=postgres -f"
    echo "   - Check PVC: kubectl -n postgres describe pvc postgres-volume-claim"
    echo "   - Connect: psql -h localhost -p 54322 -U postgres"
else
    echo "❌ PostgreSQL deployment failed or timed out"
    echo "   Check logs with: kubectl -n postgres logs -l app=postgres"
    exit 1
fi