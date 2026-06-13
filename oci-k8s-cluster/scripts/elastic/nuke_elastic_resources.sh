#!/usr/bin/env bash
# Thin wrapper — use uninstall_elastic_stack.sh for full removal.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/uninstall_elastic_stack.sh" "$@"
