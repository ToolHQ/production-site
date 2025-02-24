#!/bin/bash
minikube start --cpus=12 --memory=16000 --driver=docker --insecure-registry "10.0.0.0/24"
kubectl apply -f 1.\ minikube/ingress-nginx-controller-resources.yaml
kubectl port-forward --namespace=postgres deployment/postgres-deployment 54322:5432
minikube tunnel

ECK_RESOURCES_FOLDER=6.\ ECK
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-beats.yaml"
kubectl apply -f "$ECK_RESOURCES_FOLDER/quick-start-logstash.yaml"

ELASTIC_PASSWORD=$(kubectl get secret quickstart-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')
ELASTIC_AUTHORIZATION_HEADER="Basic $(echo -n "elastic:$ELASTIC_PASSWORD" | base64)"
curl -k -X GET https://es.localhost/_cat/templates -H "Authorization:$ELASTIC_AUTHORIZATION_HEADER"
curl -k -X PUT https://es.localhost/_index_template/template_1 -H "Authorization:$ELASTIC_AUTHORIZATION_HEADER" -H 'Content-Type:application/json' -d '{ "index_patterns": ["logs-*", "metrics-*"], "priority": 600, "data_stream": {}, "template": { "settings": { "number_of_shards": 1, "number_of_replicas": 0, "index.mapping.total_fields.limit": 2000 } } }'
curl -k -X PUT https://es.localhost/\*/_settings -H "Authorization:$ELASTIC_AUTHORIZATION_HEADER" -H 'Content-Type:application/json' -d '{ "index.number_of_replicas": 0 }'

curl -k -X PUT "https://es.localhost/logs-generic-default/_settings" -H "Authorization:$ELASTIC_AUTHORIZATION_HEADER" -H "Content-Type: application/json" -d '{ "index.mapping.total_fields.limit": 2000 }'