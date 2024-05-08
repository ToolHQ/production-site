#!/bin/bash
# Tested in 2024-05-08

## Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

## From: https://github.com/codeedu/wsl2-kubernetes?tab=readme-ov-file
# Download the latest version of Minikube
 curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
   && sudo install minikube-linux-amd64 /usr/local/bin/minikube

minikube delete
minikube start --cpus=12 --memory=16000 --driver=docker --insecure-registry "10.0.0.0/24"
minikube addons enable ingress
minikube addons enable metrics-server
minikube addons enable dashboard
kubectl apply -f 1.\ minikube/kube-dashboard-ingress.yaml

## Init both minio and nexus for blob storage and images storage
kubectl apply -f 3.\ minio/minio-resources.yaml
kubectl apply -f 4.\ nexus/nexus-resources.yaml
mkdir -p ~/.minikube/files/etc
tee ~/.minikube/files/etc/hosts << END
127.0.0.1       localhost
::1     localhost ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
192.168.49.2    minikube
192.168.49.1    host.minikube.internal
192.168.49.2    control-plane.minikube.internal
127.0.0.1 docker-nexus.localhost
END

## Uses this to expose minikube ip as localhost
minikube tunnel

## Todo: automate
## Login at minio-console.localhost:
##   Create a bucket named nexus;
##   Create an access key pair;
## Login at nexus.localhost:
##   Change password using command below:
docker exec -it minikube bash -c "cat /data/nexus/admin.password"
##   Create a new blob store named minio:
##     - Type: S3
##     - Name: minio
##     - Region: us-east-1
##     - Bucket: nexus
##     - Prefix: <leave it empty>
##     - Expiration days: -1
##     - Access Key ID: <previous value from minio step>
##     - Secret Access Key: <previous value from minio step>
##     - Encryption Type: None
##     - KMS Key ID (Optional): <leave it empty>
##     - Endpoint URL: http://minio-service.minio.svc.cluster.local:9000
##     - Max Connection Pool Size: <leave it empty>
##     - Signature Version: <leave it empty>
##     - Use path-style access: toogle ON
##   Create a new docker repo (hosted) named docker-repo:
##     - Toogle Online: true
##     - Repository Connectors > HTTP: Toogle and fill with port value "18444"
##   At Security > Realms:
##     - Enable Docker Bearer Token Realm.
##   At Security > Users:
##     - Create user with login docker and password docker123.

DOCKER_REGISTRY_HOST=docker-nexus.localhost
docker login $DOCKER_REGISTRY_HOST
docker pull node:20.13.0-alpine3.19
docker tag node:20.13.0-alpine3.19 $DOCKER_REGISTRY_HOST/repository/docker-repo/node:20.13.0-alpine3.19
docker push $DOCKER_REGISTRY_HOST/repository/docker-repo/node:20.13.0-alpine3.19
docker pull postgres:16.2-alpine3.19
docker tag postgres:16.2-alpine3.19 $DOCKER_REGISTRY_HOST/repository/docker-repo/postgres:16.2-alpine3.19
docker push $DOCKER_REGISTRY_HOST/repository/docker-repo/postgres:16.2-alpine3.19

kubectl create secret docker-registry regsecret --docker-server=http://docker-nexus.localhost/v2/ --docker-username=docker --docker-password=docker123 --docker-email=danieltakasu@gmail.com --namespace default
kubectl create secret docker-registry regsecret --docker-server=http://docker-nexus.localhost/v2/ --docker-username=docker --docker-password=docker123 --docker-email=danieltakasu@gmail.com --namespace postgres

## Run after manually setup
kubectl apply -f 6.\ postgres/postgres-resources.yaml
