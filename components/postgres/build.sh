#!/bin/bash
set -euo pipefail

DOCKER_REGISTRY_HOST=${DOCKER_REGISTRY_HOST:-127.0.0.1}
PORT=${PORT:-31444}
DOCKER_TAG="$DOCKER_REGISTRY_HOST:$PORT/repository/docker-repo/postgres:18.0-alpine3.22-1.0.0"

# Prefer rootless buildkit socket if present
BK_SOCK="${BK_SOCK:-/home/ubuntu/.local/share/buildkit/buildkitd.sock}"

# Helper function to ensure BuildKit is running
ensure_buildkit_running() {
  local uid
  uid=$(id -u)
  export XDG_RUNTIME_DIR="/run/user/$uid"
  
  # Check if BuildKit service is active
  if systemctl --user is-active --quiet buildkit.service 2>/dev/null; then
    echo "✅ BuildKit service is running"
    return 0
  fi
  
  echo "⚠️  BuildKit service not running, attempting to start..."
  
  # Try to start the service
  if systemctl --user start buildkit.service 2>/dev/null; then
    echo "✅ BuildKit service started"
    
    # Wait for socket to appear
    for i in {1..15}; do
      if [ -S "$BK_SOCK" ]; then
        echo "✅ BuildKit socket available"
        return 0
      fi
      echo "⏳ Waiting for BuildKit socket... ($i/15)"
      sleep 2
    done
    
    echo "❌ BuildKit socket did not appear"
    return 1
  else
    echo "❌ Failed to start BuildKit service"
    return 1
  fi
}

# Try to use BuildKit if available
if [ -S "$BK_SOCK" ]; then
  echo "🚀 Building via buildctl @ $BK_SOCK"
  buildctl --addr "unix://$BK_SOCK" build \
    --frontend=dockerfile.v0 \
    --local context=. \
    --local dockerfile=. \
    --output type=image,name="$DOCKER_TAG",push=true
elif ensure_buildkit_running; then
  echo "🚀 Building via buildctl @ $BK_SOCK (after service start)"
  buildctl --addr "unix://$BK_SOCK" build \
    --frontend=dockerfile.v0 \
    --local context=. \
    --local dockerfile=. \
    --output type=image,name="$DOCKER_TAG",push=true
else
  echo "ℹ️ buildkit not available — falling back to docker buildx"
  if command -v docker >/dev/null 2>&1; then
    docker buildx build . \
      --platform linux/amd64,linux/arm64 \
      -t "$DOCKER_TAG" \
      --push
  else
    echo "❌ Neither BuildKit nor Docker is available for building images"
    exit 1
  fi
fi

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
