#!/usr/bin/env bash
set -euo pipefail
dir="$(dirname "$0")"

echo "🐘 Deploying Clickhouse (External for Coroot)..."

# Apply manifest
kubectl apply -f "$dir/clickhouse.yaml"

# Wait for rollout
kubectl -n coroot rollout status deploy/clickhouse --timeout=2m

echo "✅ Clickhouse deployed."
