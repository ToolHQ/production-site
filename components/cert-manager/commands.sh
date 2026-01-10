#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")"

echo "🔒 Installing Cert-Manager..."
kubectl apply -f "$dir/cert-manager.yaml"

echo "⏳ Waiting for Cert-Manager..."
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=5m
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=5m
kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=5m

echo "📝 Configuring Issuers..."

# 1. Self-Signed Bootstrap Issuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: self-signed-issuer
spec:
  selfSigned: {}
EOF

# 2. Root CA Certificate
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dnor-root-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: dnor-root-ca
  secretName: dnor-root-ca-tls
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: self-signed-issuer
    kind: ClusterIssuer
    group: cert-manager.io
EOF

echo "⏳ Waiting for Root CA Secret (dnor-root-ca-tls)..."
for i in {1..30}; do
  if kubectl -n cert-manager get secret dnor-root-ca-tls >/dev/null 2>&1; then
    echo "✅ Root CA Secret created."
    break
  fi
  sleep 2
done

# 3. Cluster CA Issuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: dnor-ca-issuer
spec:
  ca:
    secretName: dnor-root-ca-tls
EOF

# 4. LetsEncrypt Staging
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@dnor.io
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

echo "✅ Cert-Manager configured."
