#! /bin/bash
DOCKER_REGISTRY_HOST=docker-nexus.localhost
DOCKER_TAG=$DOCKER_REGISTRY_HOST/repository/docker-repo/postgres:17beta1-alpine3.20
docker build . -t $DOCKER_TAG
docker push $DOCKER_TAG