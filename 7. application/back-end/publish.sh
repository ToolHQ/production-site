#! /bin/sh
DOCKER_REGISTRY_HOST=docker-nexus.localhost
DOCKER_TAG=$DOCKER_REGISTRY_HOST/repository/docker-repo/my-site-back-end:1.0.0
docker build -t $DOCKER_TAG .
docker push $DOCKER_TAG