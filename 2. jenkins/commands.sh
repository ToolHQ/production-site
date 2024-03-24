#!/bin/bash
# Tested in 2024-03-24
## From https://www.jenkins.io/doc/book/installing/kubernetes/#install-jenkins-with-helm-v3
helm repo add jenkinsci https://charts.jenkins.io
helm repo update
helm search repo jenkinsci
# missing, implicited
kubectl apply -f jenkins-namespace.yaml
kubectl apply -f jenkins-volume.yaml

## Workaround described if permission issues
minikube ssh
sudo chown -R 1000:1000 /data/jenkins-volume
exit 

kubectl apply -f jenkins-sa.yaml

chart=jenkinsci/jenkins
helm install jenkins -n jenkins -f jenkins-values.yaml $chart

## Save it temporary
jsonpath="{.data.jenkins-admin-password}"
secret=$(kubectl get secret -n jenkins jenkins -o jsonpath=$jsonpath)
echo $(echo $secret | base64 --decode)

## Wont be useful
jsonpath="{.spec.ports[0].nodePort}"
NODE_PORT=$(kubectl get -n jenkins -o jsonpath=$jsonpath services jenkins)
jsonpath="{.items[0].status.addresses[0].address}"
NODE_IP=$(kubectl get nodes -n jenkins -o jsonpath=$jsonpath)
echo http://$NODE_IP:$NODE_PORT/login

## Temporary
kubectl -n jenkins port-forward jenkins-0 8080:8080

## Testing ingress
kubectl apply -f jenkins-ingress.yaml

## Salvar no drivers/etc/hosts do Windows e /etc/hosts do linux
192.168.49.2 hello-world.info