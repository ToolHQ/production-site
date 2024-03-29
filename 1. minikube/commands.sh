#!/bin/bash
# Tested in 2024-03-24

## From: https://github.com/codeedu/wsl2-kubernetes?tab=readme-ov-file
# Download the latest version of Minikube
curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
# Make the binary executable
chmod +x ./minikube
# Move the binary to your executable path
sudo mv ./minikube /usr/local/bin/

minikube start --driver=docker
minikube delete
minikube start --driver=docker
minikube kubectl -- get pods -A
minikube kubectl -- version --client
minikube dashboard

## Salvar no ~/.bashrc
alias kubectl="minikube kubectl --"

## From: https://kubernetes.io/docs/tasks/access-application-cluster/ingress-minikube/
minikube addons enable ingress
minikube addons enable metrics-server

## Uses this to expose minikube ip as localhost
minikube tunnel