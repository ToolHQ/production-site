#! /bin/bash
DOCKER_REGISTRY_HOST=docker-nexus.localhost
DOCKER_TAG=$DOCKER_REGISTRY_HOST/repository/docker-repo/postgres:16.3-alpine3.20-1.0.4
docker build . -t $DOCKER_TAG
docker push $DOCKER_TAG
kubectl apply -f ./postgres-resources.yaml