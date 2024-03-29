#!/bin/bash
# Tested in 2024-03-29
## From: https://www.digitalocean.com/community/tutorials/how-to-deploy-postgres-to-kubernetes-cluster
kubectl apply -f nexus-resources.yaml
# kubectl port-forward --namespace=nexus deployment/nexus 54322:5432