#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")"

echo "🧭 Installing Kubernetes Dashboard..."

# Helper for Helm
if ! command -v helm >/dev/null 2>&1; then
  echo "📦 Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if ! helm repo list | grep -q kubernetes-dashboard; then
  helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
fi
helm repo update

echo "🚀 Deploying via Helm..."
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --namespace kubernetes-dashboard --create-namespace \
  --version 7.13.0 \
  --set service.type=NodePort \
  --set service.nodePort=31201 \
  --set kong.proxy.http.containerPort=8443 \
  --set service.targetPort=8443 \
  --set metricsScraper.enabled=true \
  --wait \
  --timeout 2m

# Admin User
echo "🔑 configuring Admin User..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

# Ingress
echo "🌐 Configuring Ingress..."
cat <<INGRESS | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: dashboard-ingress
  namespace: kubernetes-dashboard
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: dnor-ca-issuer
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - k8s.dnor.io
    secretName: k8s-tls
  rules:
  - host: k8s.dnor.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes-dashboard-kong-proxy
            port:
              number: 443
INGRESS

echo "✅ Kubernetes Dashboard Configured."
