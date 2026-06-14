#!/usr/bin/env bash
# sync_github_webhook_ips.sh — atualiza github-webhook-ip-ranges.txt a partir da API meta (T-345)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
OUT="$REPO_ROOT/components/ssdnodes/github-webhook-ip-ranges.txt"

hooks=$(curl -fsS https://api.github.com/meta | python3 -c "import sys,json; print('\n'.join(json.load(sys.stdin).get('hooks',[])))")

if [[ -z "$hooks" ]]; then
  echo "❌ hooks[] vazio em api.github.com/meta" >&2
  exit 1
fi

{
  echo "# GitHub webhook delivery IPs (hooks[] from https://api.github.com/meta)"
  echo "# Refresh: bash oci-k8s-cluster/scripts/ssdnodes/sync_github_webhook_ips.sh"
  echo "# Used by ufw_manager.sh — allow 443 from these CIDRs only (T-345)"
  echo "$hooks"
} >"$OUT"

echo "✓ Atualizado $OUT ($(echo "$hooks" | wc -l) CIDRs)"
