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

# Check for existing deployment and handle Multi-Attach errors
echo "🔍 Checking for existing PostgreSQL deployment..."
if kubectl -n postgres get deployment postgres-deployment >/dev/null 2>&1; then
    echo "⚠️  Existing PostgreSQL deployment found."
    
    # Check for stuck pods or volume attachment issues
    stuck_pods=$(kubectl -n postgres get pods -l app=postgres --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | grep -c "postgres" 2>/dev/null || echo "0")
    stuck_pods=$(echo "$stuck_pods" | tr -d '\n\r' | grep -o '[0-9]*' | head -1)
    stuck_pods=${stuck_pods:-0}
    
    if [ "$stuck_pods" -gt 0 ]; then
        echo "⚠️  Found $stuck_pods stuck pod(s). This may cause Multi-Attach errors."
        echo "   Cleaning up stuck pods..."
        
        # Force delete stuck pods
        kubectl -n postgres delete pods -l app=postgres --force --grace-period=0 2>/dev/null || true
        
        # Wait for volume detachment
        echo "⏳ Waiting 15 seconds for volume detachment..."
        sleep 15
    fi
    
    # Scale down deployment to avoid Multi-Attach errors during update
    echo "📉 Scaling down existing deployment to avoid Multi-Attach errors..."
    kubectl -n postgres scale deployment postgres-deployment --replicas=0
    
    # Wait for pods to terminate
    echo "⏳ Waiting for pods to terminate (max 60s)..."
    kubectl -n postgres wait --for=delete pod -l app=postgres --timeout=60s 2>/dev/null || true
    
    # Additional wait to ensure volume is fully detached
    echo "⏳ Waiting 10 seconds for volume detachment..."
    sleep 10
fi

# Apply Kubernetes resources
echo "🚀 Applying PostgreSQL resources..."
kubectl apply -f postgres-resources.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for PostgreSQL deployment to be ready (timeout: 5m)..."
if kubectl -n postgres rollout status deployment/postgres-deployment --timeout=5m 2>&1; then
    echo "✅ PostgreSQL deployment successful!"
    
    # Display deployment info
    echo ""
    echo "📊 Deployment Status:"
    kubectl -n postgres get deployment,pod,svc,pvc -o wide
    
    echo ""
    echo "💡 Useful commands:"
    echo "   - Port forward: kubectl port-forward --namespace=postgres deployment/postgres-deployment 54322:5432"
    echo "   - View logs: kubectl -n postgres logs -l app=postgres -f"
    echo "   - Check PVC: kubectl -n postgres describe pvc postgres-pvc"
    echo "   - Check events: kubectl -n postgres get events --sort-by='.lastTimestamp'"
    echo "   - Connect: psql -h localhost -p 54322 -U postgres"
else
    echo "❌ PostgreSQL deployment failed or timed out"
    echo ""
    echo "🔍 Troubleshooting steps:"
    
    # Check for Multi-Attach errors
    if kubectl -n postgres get events 2>/dev/null | grep -i "multi-attach\|FailedAttachVolume\|already.*used" >/dev/null; then
        echo "⚠️  Multi-Attach error detected!"
        echo "   This occurs when a volume is still attached to another pod."
        echo ""
        echo "   To resolve:"
        echo "   1. Force cleanup: kubectl -n postgres delete pods -l app=postgres --force --grace-period=0"
        echo "   2. Wait 30 seconds for volume detachment"
        echo "   3. Re-run this script"
        echo ""
        echo "   Or use manual cleanup:"
        echo "   kubectl -n postgres delete deployment postgres-deployment"
        echo "   kubectl -n postgres delete pvc postgres-pvc"
        echo "   Then re-apply the resources"
    fi
    
    echo ""
    echo "   - View pod events: kubectl -n postgres get events --sort-by='.lastTimestamp'"
    echo "   - View pod logs: kubectl -n postgres logs -l app=postgres"
    echo "   - Describe pods: kubectl -n postgres describe pods -l app=postgres"
    echo "   - Check PVC status: kubectl -n postgres describe pvc postgres-pvc"
    
    exit 1
fi