#!/usr/bin/env bash
# Headless equivalent of: k8s_ops_menu → Deploy Apps → <app> → Deploy / Rebuild.
# Uses the same _app_* helpers and log path as the TUI (logs/tui-app-deploy/).
set -euo pipefail

MENU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$MENU_DIR/.." && pwd)"
APP_NAME="${1:-ai-radar}"
APP_DIR="$REPO_ROOT/apps/$APP_NAME"
DEPLOY_SCRIPT="$APP_DIR/deploy.sh"

export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/oci-k8s-cluster/kubeconfig_tunnel.yaml}"

if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
  printf '%s\n' "No deploy.sh at $APP_DIR" >&2
  exit 1
fi

# shellcheck source=k8s_ops_menu.sh
source "$MENU_DIR/k8s_ops_menu.sh"

deploy_log_file="$(_app_new_deploy_log_file "$APP_NAME" "$(basename "$DEPLOY_SCRIPT")")"
export APP_DEPLOY_LAST_LOG_FILE="$deploy_log_file"
_app_init_deploy_log "$deploy_log_file" "$APP_NAME" "$APP_DIR" "$DEPLOY_SCRIPT"

if ! _app_check_oci_builder_logged "$deploy_log_file"; then
  _app_log_line "$deploy_log_file" "oci-builder not ready — running setup-dev-deploy.sh (non-interactive)"
  if ! _app_run_setup_dev_deploy_logged "$deploy_log_file"; then
    printf '%s\n' "setup-dev-deploy.sh failed — log: $deploy_log_file" >&2
    exit 1
  fi
  if ! _app_check_oci_builder_logged "$deploy_log_file"; then
    printf '%s\n' "oci-builder still unavailable — log: $deploy_log_file" >&2
    exit 1
  fi
fi

if ! _app_wait_for_nexus_ready_logged "$deploy_log_file"; then
  printf '%s\n' "Nexus not ready — log: $deploy_log_file" >&2
  exit 1
fi

echo "Deploy log: $deploy_log_file"
if _app_run_deploy_logged "$APP_NAME" "$APP_DIR" "$DEPLOY_SCRIPT" "$deploy_log_file"; then
  printf '%s\n' "✅ $APP_NAME deploy finished — $deploy_log_file"
  exit 0
fi
printf '%s\n' "❌ deploy failed — see $deploy_log_file" >&2
exit 1
