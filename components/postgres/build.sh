#! /bin/bash
DOCKER_REGISTRY_HOST=127.0.0.1
PORT=${PORT:-31444}
DOCKER_TAG=$DOCKER_REGISTRY_HOST:$PORT/repository/docker-repo/postgres:18.0-alpine3.22-1.0.0
docker build . -t $DOCKER_TAG
docker push $DOCKER_TAG
kubectl apply -f ./postgres-resources.yaml

# http://localhost:31444/
# docker login localhost:31444
## Edit /etc/docker/daemon.json to add:
# {
#   "insecure-registries": [
#     "127.0.0.1:31444"
#   ]
# }

# kubectl -n nexus get svc nexus-service -o wide
# ClusterIP: 10.96.45.210
# sudo bash -c 'echo "10.96.45.210 registry.local" >> /etc/hosts'


# kubectl -n kube-system edit configmap coredns
# hosts {
#     10.0.1.100 registry.local
#     fallthrough
# }
# kubectl -n kube-system rollout restart deployment coredns

# sudo mkdir -p /etc/containerd
# sudo nano /etc/containerd/config.toml
# [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
#   [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.local:31444"]
#     endpoint = ["http://registry.local:31444"]

# [plugins."io.containerd.grpc.v1.cri".registry.configs."registry.local:31444".tls]
#   insecure_skip_verify = true
# sudo systemctl restart containerd

# sudo test -f /etc/containerd/config.toml || sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null; sudo awk '/\[plugins."io.containerd.grpc.v1.cri"\]/ && !x++{print;print "  [plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"registry.local:31444\"]\n    endpoint = [\"http://registry.local:31444\"]\n\n  [plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"registry.local:31444\".tls]\n    insecure_skip_verify = true";next}1' /etc/containerd/config.toml | sudo tee /etc/containerd/config.toml.new >/dev/null && sudo mv /etc/containerd/config.toml.new /etc/containerd/config.toml && sudo systemctl restart containerd && sudo systemctl status containerd --no-pager --lines=5
