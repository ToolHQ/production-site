#! /bin/sh
DOCKER_REGISTRY_HOST=docker-nexus.localhost
DOCKER_TAG=$DOCKER_REGISTRY_HOST/repository/docker-repo/logstash:8.13.3-custom.2
docker build -t $DOCKER_TAG .
docker push $DOCKER_TAG