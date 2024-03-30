#!/bin/bash
# Tested in 2024-03-29
## From: https://www.elastic.co/guide/en/cloud-on-k8s/current/k8s-deploy-eck.html

## 1. Install custom resource definitions:
# kubectl create -f https://download.elastic.co/downloads/eck/2.12.1/crds.yaml
kubectl create -f crds.yaml

## 2. Install the operator with its RBAC rules:
# kubectl apply -f https://download.elastic.co/downloads/eck/2.12.1/operator.yaml
kubectl apply -f operator.yaml

## 3. Apply a simple Elasticsearch cluster specification, with one Elasticsearch node:
kubectl apply -f quick-start-es.yaml

## 4. Adding ingress to ES:
kubectl apply -f quick-start-es-ingress.yaml

## 5. Specify a Kibana instance and associate it with your Elasticsearch cluster:
kubectl apply -f quick-start-kibana.yaml

## 6. Adding ingress to Kibana:
kubectl apply -f quick-start-kibana-ingress.yaml