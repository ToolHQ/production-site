#!/bin/bash
source "$(dirname "$0")/../../common.sh"

echo -e "${RED}Uninstalling Parca Observability...${NC}"

helm uninstall parca -n parca
kubectl delete ns parca --ignore-not-found

echo -e "${GREEN}Parca uninstalled.${NC}"
