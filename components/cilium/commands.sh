#!/usr/bin/env bash
# Managed by Antigravity (T-096)
set -euo pipefail

echo "🧩 Tuning Cilium resources..."

# Get current version from setup script or use default
CILIUM_VERSION="1.18.2"

cilium upgrade install --version "v${CILIUM_VERSION}" \
  --wait=false \
  --values cilium-values.yaml \
  --set rollOutCiliumPods=true

echo "✅ Cilium resources tuned."
