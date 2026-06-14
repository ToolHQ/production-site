#!/bin/bash
# Delegates to the canonical cluster uninstall script (elastic-stack is archived).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/../../../oci-k8s-cluster/scripts/elastic/uninstall_elastic_stack.sh"
