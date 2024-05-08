#!/bin/bash
# Tested in 2024-03-29
## From: https://www.digitalocean.com/community/tutorials/how-to-deploy-postgres-to-kubernetes-cluster
kubectl apply -f nexus-resources.yaml
docker exec -it minikube bash -c "cat /data/nexus/admin.password"

# docker pull node:20.12.2-alpine3.19
# docker tag node:20.12.2-alpine3.19 docker-nexus.localhost/repository/docker-repo/node:20.12.2-alpine3.19
# docker login docker-nexus.localhost
docker push docker-nexus.localhost/repository/docker-repo/node:20.12.2-alpine3.19
docker pull postgres:16.2-alpine3.19
docker tag postgres:16.2-alpine3.19 docker-nexus.localhost/repository/docker-repo/postgres:16.2-alpine3.19
docker push docker-nexus.localhost/repository/docker-repo/postgres:16.2-alpine3.19

kubectl create secret docker-registry regsecret --docker-server=http://docker-nexus.localhost/v2/ --docker-username=docker --docker-password=docker123 --docker-email=danieltakasu@gmail.com --namespace postgres
