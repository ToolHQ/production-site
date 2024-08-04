#! /bin/sh

# Remove existing Buildx instance
# docker buildx rm minikubebuilder

# Create a new Buildx instance
# docker buildx create --name minikubebuilder --driver docker-container --driver-opt network=minikube

# Use the new Buildx instance
# docker buildx use minikubebuilder

## Clean build
npm cache clean -f && rm -rf node_modules/ && NODE_TLS_REJECT_UNAUTHORIZED=0 npm i

# Define Docker tag
DOCKER_REGISTRY_HOST=docker-nexus.localhost
DOCKER_TAG=$DOCKER_REGISTRY_HOST/repository/docker-repo/my-site-back-end:latest

# Build the Docker image using Buildx
docker buildx build --load --add-host=docker-nexus.localhost:192.168.49.2 --add-host=nexus.localhost:192.168.49.2 --add-host=minio.localhost:192.168.49.2 -t $DOCKER_TAG .
docker push $DOCKER_TAG

kubectl apply -f ./k8s/minikube/my-site-back-end.yaml
