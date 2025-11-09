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

## 7. To deploy an APM Server and connect it to the Elasticsearch cluster and Kibana instance you created in the quickstart, apply the following specification:
kubectl apply -f quick-start-apm-server.yaml

## 8. Adding ingress to APM Server:
kubectl apply -f quick-start-apm-server-ingress.yaml

## 9. Apply the following specification to deploy Elastic Agent with the System metrics integration to harvest CPU metrics from the Agent Pods:
kubectl apply -f quick-start-elastic-agent.yaml

## Enterprise only: Deploying Elastic Maps Server can be done with a simple manifest:
# kubectl apply -f quick-start-elastic-maps.yaml

## 10. Apply the following specification to deploy Filebeat and collect the logs of all containers running in the Kubernetes cluster.
kubectl apply -f quick-start-beats.yaml

## 11. Add the following specification to create a minimal Logstash deployment that will listen to a Beats agent or Elastic Agent configured to send to Logstash on port 5044, create the service and write the output to an Elasticsearch cluster named quickstart.
kubectl apply -f quick-start-logstash.yaml