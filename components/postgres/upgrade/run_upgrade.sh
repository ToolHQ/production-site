DOCKER_REGISTRY_HOST=docker-nexus.localhost
DOCKER_TAG=$DOCKER_REGISTRY_HOST/repository/docker-repo/pg_upgrade:1.0.2
docker build . -t $DOCKER_TAG
docker push $DOCKER_TAG
kubectl apply -f ./upgrade.yaml