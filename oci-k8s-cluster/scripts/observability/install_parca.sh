#!/bin/bash
source "$(dirname "$0")/../../common.sh"

echo -e "${BLUE}Installing Parca Observability (Continuous Profiling)...${NC}"

# Add repo
echo -e "${YELLOW}Adding Parca Helm Repo...${NC}"
helm repo add parca https://parca-dev.github.io/helm-charts
helm repo update

# Create namespace
kubectl create ns parca --dry-run=client -o yaml | kubectl apply -f -

# Install Parca
# Parca Chart installs Server and Agent by default
echo -e "${YELLOW}Deploying Parca via Helm...${NC}"
helm upgrade --install parca parca/parca \
  --namespace parca \
  --set agent.enabled=true \
  --set server.enabled=true \
  --wait

echo -e "${GREEN}Parca installed successfully!${NC}"

# Get the Service NodePort or setup port-forward instructions
echo -e "${BLUE}Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=parca -n parca --timeout=300s

echo -e "${GREEN}Parca is Ready!${NC}"
echo -e "${YELLOW}You can access Parca by forwarding the port:${NC}"
echo -e "kubectl port-forward -n parca svc/parca 7070:7070"
echo -e "Then open http://localhost:7070"
