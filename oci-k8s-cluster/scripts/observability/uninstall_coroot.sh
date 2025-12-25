#!/bin/bash
source "$(dirname "$0")/../../common.sh"

echo -e "${RED}Uninstalling Coroot Observability...${NC}"

helm uninstall coroot -n coroot
kubectl delete ns coroot --ignore-not-found

echo -e "${GREEN}Coroot uninstalled.${NC}"
