#!/bin/bash
# Tested in 2024-03-24
# https://github.com/kubernetes/minikube/issues/2840#issuecomment-481245804
# https://minikube.sigs.k8s.io/docs/tutorials/nginx_tcp_udp_ingress/
# minikube addons enable ingress
# kubectl patch configmap tcp-services -n ingress-nginx --patch '{"data":{"54322":"postgres/postgres-service:5432"}}'
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --patch '{"spec":{"template":{"spec":{"hostNetwork":false}}}}'
kubectl patch configmap tcp-services -n ingress-nginx --patch '{"data":{"54322":"postgres/postgres-service:5432","6379":"redis/redis-service:6379"}}'

kubectl patch deployment ingress-nginx-controller --patch "$(cat ingress-nginx-controller-patch.yaml)" -n ingress-nginx