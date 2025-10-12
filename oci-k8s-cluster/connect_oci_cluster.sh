#!/usr/bin/env bash
set -euo pipefail

MASTER_PUBLIC_IP="150.136.34.254"
MASTER_PRIVATE_IP="10.0.1.100"
KEY_PATH="$HOME/.ssh/oci-ssh-key-2025-06-19.key"
KUBECONFIG_PATH="$HOME/.kube/oci-config"

echo "🌐 Ensuring local port 6443 is free..."
pkill -f "ssh .* -L 6443:" 2>/dev/null || true
sleep 1

echo "🌐 Starting SSH tunnel to ${MASTER_PUBLIC_IP} -> ${MASTER_PRIVATE_IP}:6443 ..."
ssh -i "$KEY_PATH" -f -L 6443:${MASTER_PRIVATE_IP}:6443 ubuntu@${MASTER_PUBLIC_IP} -N
echo "✅ Tunnel active on https://127.0.0.1:6443"

echo "🛠️  Adjusting kubeconfig for localhost + insecure TLS (local use only)..."
kubectl --kubeconfig "$KUBECONFIG_PATH" config set-cluster kubernetes --server=https://127.0.0.1:6443 >/dev/null
kubectl --kubeconfig "$KUBECONFIG_PATH" config set-cluster kubernetes --insecure-skip-tls-verify=true >/dev/null

export KUBECONFIG="$KUBECONFIG_PATH"
echo "🔎 Verifying connectivity..."
kubectl cluster-info
kubectl get nodes -o wide
echo "✅ Connected to OCI cluster via SSH tunnel."
