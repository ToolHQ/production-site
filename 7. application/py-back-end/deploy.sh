#! /bin/sh

# Define Docker tag
TAG_VERSION=$(date +%s)
DOCKER_REGISTRY_HOST=docker-nexus.localhost
DOCKER_TAG=$DOCKER_REGISTRY_HOST/repository/docker-repo/my-site-py-back-end:$TAG_VERSION
DOCKER_TAG_LATEST=$DOCKER_REGISTRY_HOST/repository/docker-repo/my-site-py-back-end:latest

# Build the Docker image using Buildx
docker buildx build --load --add-host=docker-nexus.localhost:192.168.49.2 --add-host=nexus.localhost:192.168.49.2 --add-host=minio.localhost:192.168.49.2 -t $DOCKER_TAG .
docker push $DOCKER_TAG
docker tag $DOCKER_TAG $DOCKER_TAG_LATEST
docker push $DOCKER_TAG_LATEST

sed -i "s|image: .*|image: $DOCKER_TAG|" ./k8s/minikube/my-site-py-back-end.yaml

kubectl apply -f ./k8s/minikube/my-site-py-back-end.yaml
