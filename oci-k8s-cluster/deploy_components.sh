#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ────────────────────────────────────────────────
# Load shared helpers
source "$(dirname "$0")/common.sh"

COMPONENTS_DIR="$(dirname "$0")/../components"
REMOTE_BASE="/home/ubuntu/deployments"

# ────────────────────────────────────────────────
# List all component directories
list_components() {
  find "$COMPONENTS_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
}

# ────────────────────────────────────────────────
# Prompt user to select components (supports gum)
prompt_components() {
  mapfile -t components < <(list_components)
  if command -v gum >/dev/null 2>&1; then
    echo "📦 Select components to deploy (SPACE = toggle, ENTER to confirm):" >&2
    mapfile -t selected < <(gum choose --no-limit "${components[@]}")
  else
    echo "📦 Available components:" >&2
    for i in "${!components[@]}"; do
      printf "  [%d] %s\n" "$((i+1))" "${components[$i]}" >&2
    done
    echo >&2
    read -rp "Enter numbers (comma-separated) or ENTER for all: " choice
    if [[ -z "${choice:-}" ]]; then
      selected=("${components[@]}")
    else
      selected=()
      IFS=',' read -ra nums <<<"$choice"
      for n in "${nums[@]}"; do
        n="${n//[!0-9]/}"
        (( n>=1 && n<=${#components[@]} )) || { echo "⚠️ Invalid index '$n' ignored." >&2; continue; }
        selected+=("${components[$((n-1))]}")
      done
    fi
  fi

  if [[ "${#selected[@]}" -eq 0 ]]; then
    echo "🚫 No components selected." >&2
    exit 1
  fi

  # Only print the selected component names to stdout
  printf "%s\n" "${selected[@]}"
}

# ────────────────────────────────────────────────
# Deploy a single component
deploy_component() {
  local name="$1"
  local src="$COMPONENTS_DIR/$name"

  log_node "$MASTER_NODE" "🚀 Deploying component '$name'"
  run_remote "$MASTER_NODE" "mkdir -p '$REMOTE_BASE/$name' && rm -rf '$REMOTE_BASE/$name/*'"
  scp_to_remote "$MASTER_NODE" "$src" "$REMOTE_BASE/"

  run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail <<'EOF'
cd '$REMOTE_BASE/$name'

echo '📁 Working in:' \$(pwd)
if [ -f ./commands.sh ]; then
  echo '▶ Running commands.sh...'
  chmod +x ./commands.sh
  ./commands.sh || echo '⚠️ commands.sh exited non-zero.'
fi

if ls *.yaml >/dev/null 2>&1; then
  echo '⚙️ Applying YAML manifests...'
  kubectl apply -f . || echo '⚠️ Some manifests failed to apply.'
else
  echo 'ℹ️ No YAML manifests found.'
fi

echo '✅ Component $name deployment complete.'
EOF"
}

# ────────────────────────────────────────────────
# Deploy all or selected components
deploy_selected() {
  local -a comps=("$@")
  for comp in "${comps[@]}"; do
    deploy_component "$comp"
  done
}

# ────────────────────────────────────────────────
# Main
main() {
  local -a selection
  if [[ $# -gt 0 ]]; then
    selection=("$@")
  else
    mapfile -t selection < <(prompt_components)
  fi
  deploy_selected "${selection[@]}"
}

main "$@"