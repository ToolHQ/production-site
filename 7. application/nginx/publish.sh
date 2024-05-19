#! /bin/sh
DOCKER_REGISTRY_HOST=docker-nexus.localhost
DOCKER_TAG=$DOCKER_REGISTRY_HOST/repository/docker-repo/my-site-nginx:1.0.6
docker build -t $DOCKER_TAG .
docker push $DOCKER_TAG
