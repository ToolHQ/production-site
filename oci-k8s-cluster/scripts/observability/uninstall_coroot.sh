#!/bin/bash
OBS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$OBS_DIR/../../common.sh"

uninstall_coroot() {
  echo -e "${RED}Uninstalling Coroot Observability (Full Stack) on REMOTE MASTER...${NC}"
  
  run_remote_stream "$MASTER_NODE" 'bash -s' <<'EOF'
    set -e
    # Colors for remote
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    NC='\033[0m'
    
    echo -e "${YELLOW}Uninstalling Helm release...${NC}"
    helm uninstall coroot -n coroot || true
    
    echo -e "${YELLOW}Deleting standalone ClickHouse resources...${NC}"
    kubectl delete deployment clickhouse -n coroot --ignore-not-found
    kubectl delete service clickhouse -n coroot --ignore-not-found
    kubectl delete configmap clickhouse-users-config -n coroot --ignore-not-found
    
    echo -e "${YELLOW}Deleting namespace (non-blocking)...${NC}"
    kubectl delete ns coroot --wait=false --ignore-not-found
    
    echo -e "${YELLOW}Waiting for namespace deletion to complete (max 60s)...${NC}"
    for i in {1..60}; do
      if ! kubectl get ns coroot &>/dev/null; then
        echo -e "${GREEN}✓ Namespace 'coroot' deleted${NC}"
        break
      fi
      sleep 1
    done
    
    echo -e "${YELLOW}Verifying cleanup...${NC}"
    # Check if namespace still exists
    if kubectl get ns coroot &>/dev/null; then
      echo -e "${YELLOW}⚠ Namespace 'coroot' is being deleted (may take a few more seconds)${NC}"
    else
      echo -e "${GREEN}✓ Namespace completely removed${NC}"
    fi
    
    # Check for any remaining resources
    REMAINING=$(kubectl get all -n coroot 2>/dev/null | wc -l)
    if [ "$REMAINING" -gt 0 ]; then
      echo -e "${YELLOW}⚠ Some resources still terminating:${NC}"
      kubectl get all -n coroot 2>/dev/null || true
    else
      echo -e "${GREEN}✓ All resources removed${NC}"
    fi
    
    echo -e "${GREEN}Coroot uninstall complete!${NC}"
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    uninstall_coroot
fi
