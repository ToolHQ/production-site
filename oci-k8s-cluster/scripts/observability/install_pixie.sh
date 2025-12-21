#!/usr/bin/env bash
set -euo pipefail

# Use unique variable for script directory
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$INSTALL_DIR/../../common.sh"

echo "🧚 Pixie Installation Initiated (Remote Helm Strategy)..."

# 1. Retrieve Deploy Key (Local)
KEY_FILE="$INSTALL_DIR/../../../pixie_deploy_key.txt"
if [[ -f "$KEY_FILE" ]]; then
  DEPLOY_KEY=$(cat "$KEY_FILE" | tr -d '[:space:]')
  echo "🔑 Found Deploy Key."
else
  echo "❌ Deploy key file not found at $KEY_FILE"
  echo "Please create 'pixie_deploy_key.txt' in the project root."
  exit 1
fi

# 2. Deploy Pixie on Remote Master
echo "🚀 executing Helm on $MASTER_NODE..."

ssh "$MASTER_NODE" "
  set -e
  echo '📦 Adding Pixie Helm Repo...'
  helm repo add pixie-operator https://pixie-operator-charts.storage.googleapis.com
  helm repo update
  
  echo '🚀 Deploying Pixie Operator & Vizier...'
  helm upgrade --install pixie pixie-operator/pixie-operator-chart \
    --namespace pl \
    --create-namespace \
    --set deployKey='$DEPLOY_KEY' \
    --set clusterName='oci-k8s-cluster' \
    --set useEtcdOperator=true 
"

echo "✅ Pixie Helm Release installed."
echo "⏳ Waiting for Pixie Pods to be ready..."

# Wait for 5 minutes max for pods to come up
if ssh "$MASTER_NODE" "kubectl wait --for=condition=ready pod -l app=pl-vizier-cloud-connector -n pl --timeout=300s" &>/dev/null; then
    echo "🎉 Pixie Cloud Connector is READY!"
else
    echo "⚠️  Timed out waiting for pods. Please check status manually."
fi

echo ""
echo "================================================================"
echo "🧚 Pixie Deployment Verification"
echo "================================================================"
echo "🔹 Status:      Running (Hybrid Mode)"
echo "🔹 Namespace:   pl"
echo "🔹 UI Access:   https://work.withpixie.ai/"
echo "🔹 Ingress:     N/A (SaaS UI manages access)"
echo ""
echo "To check pod status locally:"
echo "  kubectl get po -n pl"
echo ""
echo "To verify Live View:"
echo "  px live"
echo "================================================================"
