#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------
# 🧭 Configuration
# ---------------------------------------------------------------
MASTER_NODE="oci-k8s-master"
DASHBOARD_VERSION="${1:-v2.7.0}"
NAMESPACE="kubernetes-dashboard"

# ---------------------------------------------------------------
# 🧩 Helpers
# ---------------------------------------------------------------
run_remote() {
  local host="$1"
  local cmd="$2"
  echo -e "\033[36m[$host]\033[0m → $cmd"
  ssh -o StrictHostKeyChecking=no ubuntu@"$host" "bash -c '$cmd'"
}

# ---------------------------------------------------------------
# 🚀 Deploy Kubernetes Dashboard
# ---------------------------------------------------------------
echo "📊 Deploying Kubernetes Dashboard $DASHBOARD_VERSION on $MASTER_NODE..."

run_remote "$MASTER_NODE" "
  set -euo pipefail

  echo '🔍 Checking cluster connectivity...'
  kubectl get nodes >/dev/null

  echo '📦 Applying Dashboard manifests...'
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/$DASHBOARD_VERSION/aio/deploy/recommended.yaml --validate=false

  echo '👤 Creating admin service account and binding...'
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: ${NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: ${NAMESPACE}
EOF

  echo '🔑 Generating login token...'
  kubectl -n ${NAMESPACE} create token admin-user > /tmp/dashboard_token.txt

  echo '✅ Dashboard deployed!'
  echo 'Token saved at /tmp/dashboard_token.txt'
  echo 'You can retrieve it anytime with:'
  echo '  kubectl -n ${NAMESPACE} create token admin-user'

  echo '🌐 To access the dashboard securely, run this from your local machine:'
  echo '  ssh -L 8443:localhost:8443 ubuntu@${MASTER_NODE}'
  echo '  kubectl -n ${NAMESPACE} port-forward service/kubernetes-dashboard 8443:443'
  echo 'Then open: https://localhost:8443'
"

# ---------------------------------------------------------------
# ✅ Summary
# ---------------------------------------------------------------
echo ""
echo "✅ Dashboard deployment triggered successfully on ${MASTER_NODE}."
echo "   You can re-run this script anytime to update or redeploy the dashboard."
