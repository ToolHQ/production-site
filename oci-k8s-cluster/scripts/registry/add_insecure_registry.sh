#!/bin/bash
set -euo pipefail
# Adds an insecure registry to containerd config across cluster nodes

REGISTRY_IP="192.168.1.168"

REGISTRY_PORT="18444"
REGISTRY_ENDPOINT="http://$REGISTRY_IP:$REGISTRY_PORT"
HOST_KEY="$REGISTRY_IP:$REGISTRY_PORT"

CONFIG_SNIPPET="
[plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"$HOST_KEY\"]
  endpoint = [\"$REGISTRY_ENDPOINT\"]

[plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"$HOST_KEY\".tls]
  insecure_skip_verify = true
"

NODES=("oci-k8s-master" "oci-k8s-node-1" "oci-k8s-node-2" "oci-k8s-node-3")

for node in "${NODES[@]}"; do
    echo "🔧 patching $node..."
    
    ssh "$node" "
      if grep -q \"$HOST_KEY\" /etc/containerd/config.toml; then
         echo '  -> Already configured.'
      else
         echo '$CONFIG_SNIPPET' | sudo tee -a /etc/containerd/config.toml
         sudo systemctl restart containerd
         echo '  -> Configured and Restarted.'
      fi
    "
done

echo "✅ Registry fix applied to all nodes."
