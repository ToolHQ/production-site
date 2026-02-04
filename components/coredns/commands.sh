#!/usr/bin/env bash
# Managed by Antigravity (T-096)
set -euo pipefail

echo "🧩 Tuning CoreDNS resources..."
kubectl apply -f coredns-resources.yaml
echo "✅ CoreDNS resources tuned."
