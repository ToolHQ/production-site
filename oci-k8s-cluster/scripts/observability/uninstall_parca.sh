#!/bin/bash
OBS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$OBS_DIR/../../common.sh"

uninstall_parca() {
  echo -e "${RED}Uninstalling Parca Observability on REMOTE MASTER...${NC}"
  
  run_remote_stream "$MASTER_NODE" 'bash -s' <<'EOF'
    set -e
    # Colors for remote
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    NC='\033[0m'
    
    helm uninstall parca -n parca || true
    kubectl delete ns parca --ignore-not-found
    
    echo -e "${GREEN}Parca uninstalled.${NC}"
EOF
}

# if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
#     uninstall_parca
# fi
