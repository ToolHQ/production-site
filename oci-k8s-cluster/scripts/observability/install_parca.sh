#!/bin/bash
OBS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$OBS_DIR/../../common.sh"

install_parca() {
  echo -e "${BLUE}Installing Parca Observability (Continuous Profiling) on REMOTE MASTER...${NC}"

  # Copy values file first
  echo -e "${YELLOW}Copying generic values file to remote...${NC}"
  scp -o StrictHostKeyChecking=accept-new -o BatchMode=yes \
    "$OBS_DIR/../../../components/observability/parca-values.yaml" \
    "$MASTER_NODE:/tmp/parca-values.yaml"

  run_remote_stream "$MASTER_NODE" 'bash -s' <<'EOF'
    set -e
    # Colors for remote
    YELLOW='\033[1;33m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    echo -e "${YELLOW}Adding Parca Helm Repo...${NC}"
    helm repo add parca https://parca-dev.github.io/helm-charts
    helm repo update

    # Create namespace
    kubectl create ns parca --dry-run=client -o yaml | kubectl apply -f -

    # Install Parca with Custom Values
    echo -e "${YELLOW}Deploying Parca via Helm (Timeout: 2m)...${NC}"
    
    helm upgrade --install parca parca/parca \
      --namespace parca \
      --values /tmp/parca-values.yaml \
      --timeout 2m

    echo -e "${GREEN}Parca installed successfully!${NC}"
    
    # Wait for pods
    echo -e "${BLUE}Waiting for pods to be ready...${NC}"
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=parca-server -n parca --timeout=300s
EOF

  echo -e "${GREEN}Parca is Ready (Remote Deployment)!${NC}"
  echo -e "${YELLOW}Access URL: https://parca.dnor.io${NC}"
}

# Auto-run block removed to prevent accidental execution during sourcing
# if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
#     install_parca
# fi
