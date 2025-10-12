#!/usr/bin/env bash
set -euo pipefail

# ────────────────────────────────────────────────
# Configuration
# ────────────────────────────────────────────────
DASHBOARD_VERSION="${1:-v2.7.0}"
NAMESPACE="kubernetes-dashboard"
KUBECONFIG="$HOME/.kube/oci-config"

# ────────────────────────────────────────────────
# Functions
# ────────────────────────────────────────────────
log()  { echo -e "\033[36m$1\033[0m"; }
ok()   { echo -e "\033[32m✅ $1\033[0m"; }
warn() { echo -e "\033[33m⚠️  $1\033[0m"; }

# ────────────────────────────────────────────────
# 1️⃣  Verify connection
# ────────────────────────────────────────────────
log "🔍 Verifying cluster connectivity..."
if kubectl --kubeconfig="$KUBECONFIG" version --client=true &>/dev/null; then
  ok "Connected to cluster."
else
  echo "❌ Failed to authenticate with cluster. Run ./connect_oci_cluster.sh first."
  exit 1
fi

# ────────────────────────────────────────────────
# 2️⃣  Create namespace if missing
# ────────────────────────────────────────────────
if ! kubectl --kubeconfig="$KUBECONFIG" get ns "$NAMESPACE" >/dev/null 2>&1; then
  kubectl --kubeconfig="$KUBECONFIG" create namespace "$NAMESPACE"
  ok "Namespace $NAMESPACE created."
else
  warn "Namespace $NAMESPACE already exists."
fi

# ────────────────────────────────────────────────
# 3️⃣  Deploy dashboard
# ────────────────────────────────────────────────
log "📦 Applying Kubernetes Dashboard manifests ($DASHBOARD_VERSION)..."
kubectl --kubeconfig="$KUBECONFIG" apply -f \
  "https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/aio/deploy/recommended.yaml" \
  --namespace "$NAMESPACE" --validate=false

# ────────────────────────────────────────────────
# 4️⃣  Create admin user + role binding (idempotent)
# ────────────────────────────────────────────────
cat <<EOF | kubectl --kubeconfig="$KUBECONFIG" apply -f -
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

ok "Admin service account and binding ensured."

# ────────────────────────────────────────────────
# 5️⃣  Wait until dashboard service is ready
# ────────────────────────────────────────────────
log "⏳ Waiting for Dashboard pods to be ready..."
kubectl --kubeconfig="$KUBECONFIG" -n "$NAMESPACE" rollout status deploy/kubernetes-dashboard --timeout=120s || true

# ────────────────────────────────────────────────
# 6️⃣  Print login token
# ────────────────────────────────────────────────
TOKEN=$(kubectl --kubeconfig="$KUBECONFIG" -n "$NAMESPACE" create token admin-user)
ok "Token generated (valid ~1h):"
echo "$TOKEN"

# ────────────────────────────────────────────────
# 7️⃣  Access instructions
# ────────────────────────────────────────────────
cat <<EOF

🌐 Access Dashboard:
  kubectl -n ${NAMESPACE} port-forward service/kubernetes-dashboard 8443:443
  https://localhost:8443

Use the token above for login.

EOF
