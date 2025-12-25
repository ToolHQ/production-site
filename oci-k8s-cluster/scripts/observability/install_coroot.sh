#!/bin/bash
source "$(dirname "$0")/../../common.sh"

echo -e "${BLUE}Installing Coroot Observability (Community Edition)...${NC}"

# Add repo
echo -e "${YELLOW}Adding Coroot Helm Repo...${NC}"
helm repo add coroot https://coroot.github.io/helm-charts
helm repo update

# Create namespace
kubectl create ns coroot --dry-run=client -o yaml | kubectl apply -f -

# Install Coroot (Community Edition, Self-Hosted)
# We enable standard embedded clickhouse and prometheus for a "batteries-included" experience
# Reference: https://github.com/coroot/helm-charts
echo -e "${YELLOW}Deploying Coroot via Helm...${NC}"
helm upgrade --install coroot coroot/coroot \
  --namespace coroot \
  --set clickhouse.enabled=true \
  --set prometheus.enabled=true \
  --wait

echo -e "${GREEN}Coroot installed successfully!${NC}"

# Get the Service NodePort or setup port-forward instructions
echo -e "${BLUE}Waiting for pods to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=coroot -n coroot --timeout=300s

echo -e "${GREEN}Coroot is Ready!${NC}"
echo -e "${YELLOW}You can access Coroot by forwarding the port:${NC}"
echo -e "kubectl port-forward -n coroot svc/coroot 8080:8080"
echo -e "Then open http://localhost:8080"
