#! /bin/bash
DOCKER_REGISTRY_HOST=docker-nexus.localhost
DOCKER_TAG=$DOCKER_REGISTRY_HOST/repository/docker-repo/postgres:16.6-alpine3.21-1.0.1
docker build . -t $DOCKER_TAG
docker push $DOCKER_TAG
kubectl apply -f ./postgres-resources.yaml