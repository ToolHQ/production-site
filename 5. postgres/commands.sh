#!/bin/bash
# Tested in 2024-03-24
## From: https://www.digitalocean.com/community/tutorials/how-to-deploy-postgres-to-kubernetes-cluster
kubectl apply -f postgres-resources.yaml
kubectl port-forward --namespace=postgres deployment/postgres 54322:5432