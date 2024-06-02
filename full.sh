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
kubectl apply -f 1.\ minikube/ingress-nginx-controller-deployment.yaml
kubectl apply -f 1.\ minikube/ingress-nginx-controller-configmap.yaml

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
127.0.0.1 nexus.localhost
127.0.0.1 my-site.localhost
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
##     - Use path-style access: toogle on
##   Create a new docker repo (hosted) named docker-repo:
##     - Toogle Online: true
##     - Repository Connectors > HTTP: Toogle and fill with port value "18444"
##   At Security > Realms:
##     - Enable Docker Bearer Token Realm.
##   At Security > Users:
##     - Create user with login docker and password docker123.

DOCKER_REGISTRY_HOST=docker-nexus.localhost
docker login $DOCKER_REGISTRY_HOST
docker pull node:22.2.0-alpine3.20
docker tag node:22.2.0-alpine3.20 $DOCKER_REGISTRY_HOST/repository/docker-repo/node:22.2.0-alpine3.20
docker push $DOCKER_REGISTRY_HOST/repository/docker-repo/node:22.2.0-alpine3.20
docker pull postgres:16.2-alpine3.19
docker tag postgres:16.2-alpine3.19 $DOCKER_REGISTRY_HOST/repository/docker-repo/postgres:16.2-alpine3.19
docker push $DOCKER_REGISTRY_HOST/repository/docker-repo/postgres:16.2-alpine3.19

kubectl create secret docker-registry regsecret --docker-server=http://docker-nexus.localhost/v2/ --docker-username=docker --docker-password=docker123 --docker-email=danieltakasu@gmail.com --namespace default
kubectl create secret docker-registry regsecret --docker-server=http://docker-nexus.localhost/v2/ --docker-username=docker --docker-password=docker123 --docker-email=danieltakasu@gmail.com --namespace postgres

## Run after manually setup
kubectl apply -f 5.\ postgres/postgres-resources.yaml

## Now lets configure the ECK
ECK_RESOURCES_FOLDER=6.\ ECK
kubectl create -f "$ECK_RESOURCES_FOLDER/crds.yaml"
kubectl apply -f "$ECK_RESOURCES_FOLDER/operator.yaml"

## ElasticSearch
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-es.yaml"
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-es-ingress.yaml"
### Uses the command bellow to get the password (user is elastic):
ELASTIC_PASSWORD=$(kubectl get secret quickstart-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
echo $ELASTIC_PASSWORD
ELASTIC_AUTHORIZATION_HEADER="Basic $(echo -n "elastic:$ELASTIC_PASSWORD" | base64)"
curl -k -X GET https://es.localhost/_cat/templates -H "Authorization:$ELASTIC_AUTHORIZATION_HEADER"
curl -k -X PUT https://es.localhost/_index_template/template_1 -H "Authorization:$ELASTIC_AUTHORIZATION_HEADER" -H 'Content-Type:application/json' -d '{ "index_patterns": ["*"], "priority": 600, "data_stream": {}, "template": { "settings": { "number_of_shards": 1, "number_of_replicas": 0 } } }'
curl -k -X PUT https://es.localhost/\*/_settings -H "Authorization:$ELASTIC_AUTHORIZATION_HEADER" -H 'Content-Type:application/json' -d '{ "index.number_of_replicas": 0 }'

## Kibana
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-kibana.yaml"
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-kibana-ingress.yaml"

## APM Server
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-apm-server.yaml"
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-apm-server-ingress.yaml"

## Elastic Agent
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-elastic-agent.yaml"

## Beats
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-beats.yaml"

## Logstash
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-logstash.yaml"

## Sample application
cd 7.\ application/nginx
sh publish.sh
cd ../..
kubectl apply -f 7.\ application/nginx/k8s/minikube/my-site-nginx.yaml

## Back-end
cd 7.\ application/back-end
sh deploy.sh
cd ../..
# kubectl apply -f ./k8s/minikube/my-site-back-end.yaml

## Todo: automate
## Login at minio-console.localhost:
##   Create a bucket named nexus-npm-repo;
##   Create a bucket named nexus-npm-proxy;
##   Create a bucket named nexus-npm-group;
## Login at nexus.localhost:
##   Create new blob stores named minio-npm-repo, minio-npm-proxy and minio-npm-group:
##     - Type: S3
##     - Name: minio-npm-repo, minio-npm-proxy and minio-npm-group
##     - Region: us-east-1
##     - Bucket: nexus-npm-repo, nexus-npm-proxy and nexus-npm-group
##     - Prefix: <leave it empty>
##     - Expiration days: -1
##     - Access Key ID: <previous value from minio step>
##     - Secret Access Key: <previous value from minio step>
##     - Encryption Type: None
##     - KMS Key ID (Optional): <leave it empty>
##     - Endpoint URL: http://minio-service.minio.svc.cluster.local:9000
##     - Max Connection Pool Size: <leave it empty>
##     - Signature Version: <leave it empty>
##     - Use path-style access: toogle on
## Login at nexus.localhost:
##   1. Create a new npm repo (hosted) named npm-repo:
##       - Toogle Online: true
##       - Blob store: minio-npm-repo
##   2. Create a new npm repo (proxy) named npm-proxy:
##       - Toogle Online: true
##       - Remote storage: https://registry.npmjs.org
##       - Blob store: minio-npm-proxy
##   3. Create a new npm repo (group) named npm-group:
##       - Toogle Online: true
##       - Blob store: minio-npm-group
##       - Adds members in order: minio-npm-repo, minio-npm-proxy
##   4. At Security > Realms:
##     - Enable npm Bearer Token Realm.

npm login --scope=@dnorio --registry=http://nexus.localhost/repository/npm-repo
