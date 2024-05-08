#!/bin/bash
# Tested in 2024-03-24

## Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

## From: https://github.com/codeedu/wsl2-kubernetes?tab=readme-ov-file
# Download the latest version of Minikube
 curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
   && sudo install minikube-linux-amd64 /usr/local/bin/minikube

minikube delete
minikube start --cpus=12 --memory=16000 --driver=docker --insecure-registry "10.0.0.0/24"
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard

minikube tunnel
