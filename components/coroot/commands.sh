#!/usr/bin/env bash
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$dir/../.." && pwd)"
helm_cmd="$repo_root/tools/helm_compat.sh"

echo "🔭 Installing Coroot Observability..."

# Check Repo
if ! "$helm_cmd" repo list | grep -q coroot; then
    "$helm_cmd" repo add coroot https://coroot.github.io/helm-charts
fi
"$helm_cmd" repo update coroot

# Deploy
kubectl create ns coroot --dry-run=client -o yaml | kubectl apply -f -

# Fetch Clickhouse Password if exists
CH_PASSWORD=""
if kubectl -n coroot get secret coroot-clickhouse >/dev/null 2>&1; then
    CH_PASSWORD=$(kubectl get secret --namespace "coroot" coroot-clickhouse -o jsonpath="{.data.admin-password}" | base64 -d)
    echo "🔑 Found existing Clickhouse password."
fi

echo "🚀 Upgrading Coroot..."
kubectl apply -f "$dir/coroot-sa.yaml"

# Prepare args
ARGS=("--namespace" "coroot" "--values" "$dir/values.yaml" "--timeout" "5m" "--wait")
if [ -n "$CH_PASSWORD" ]; then
    ARGS+=("--set" "clickhouse.auth.password=$CH_PASSWORD")
fi

"$helm_cmd" upgrade --install coroot coroot/coroot "${ARGS[@]}"


echo "✅ Coroot installed."
