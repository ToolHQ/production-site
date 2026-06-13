#!/bin/bash
set -euo pipefail

# Elastic Stack Smart Build Script
# Builds custom images for Elasticsearch, Logstash, Kibana, Filebeat
# Reference: ../postgres/build.sh

COMPONENTS=("elasticsearch" "logstash" "kibana" "filebeat")

# Function to detect registry host and port dynamically
detect_registry() {
  # 1. try active Nexus service
  local nexus_ip
  nexus_ip=$(kubectl get svc -n nexus nexus-docker -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
  
  if [[ -n "$nexus_ip" ]]; then
     # Check if we are on the cluster node (can reach ClusterIP?) or need NodePort
     # For buildkit on host, usually localhost:NodePort is safest if NodePort is open
     local nodeport
     nodeport=$(kubectl get svc -n nexus nexus-docker -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || "31444")
     
     # If we are effectively on a node, return localhost:NodePort
     echo "127.0.0.1:${nodeport:-31444}"
  else
     # Fallback
     echo "127.0.0.1:31444"
  fi
}

# Allow override from env, otherwise detect
if [[ -n "${DOCKER_REGISTRY_HOST:-}" && -n "${PORT:-}" ]]; then
   REGISTRY_HOST="$DOCKER_REGISTRY_HOST"
   REGISTRY_PORT="$PORT"
else
   DETECTED=$(detect_registry)
   REGISTRY_HOST="${DETECTED%%:*}"
   REGISTRY_PORT="${DETECTED##*:}"
   echo "🔍 Auto-detected Registry: $REGISTRY_HOST:$REGISTRY_PORT"
fi

BASE_REPO="${REGISTRY_HOST}:${REGISTRY_PORT}/repository/docker-repo"
HASH_FILE=".build_hashes"

# Ensure Hash File exists
touch "$HASH_FILE"

# --- BuildKit Helper (Reused from Postgres) ---
BK_SOCK="${BK_SOCK:-/home/ubuntu/.local/share/buildkit/buildkitd.sock}"

ensure_buildkit_running() {
  local uid=$(id -u)
  export XDG_RUNTIME_DIR="/run/user/$uid"
  
  # Check if service is active AND socket exists
  if systemctl --user is-active --quiet buildkit.service 2>/dev/null; then
      if [ -S "$BK_SOCK" ]; then
          return 0
      fi
      # Service is active aka "Zombie" (file deleted), so restart it
      echo "⚠️  BuildKit active but socket missing. Restarting..."
      systemctl --user restart buildkit.service 2>/dev/null
  else
      # Service inactive, start it
      systemctl --user start buildkit.service 2>/dev/null
  fi

  for i in {1..10}; do [ -S "$BK_SOCK" ] && return 0; sleep 1; done
  return 1
}

build_image() {
    local component=$1
    local context="docker/$component"
    local dockerfile="$context/Dockerfile"
    
    if [ ! -f "$dockerfile" ]; then
        echo "⚠️  No Dockerfile found for $component. Skipping."
        return 0
    fi

    # Calculate Hash
    local current_hash=$(md5sum "$dockerfile" | awk '{print $1}')
    local last_hash=$(grep "^$component=" "$HASH_FILE" | cut -d= -f2 || echo "")
    
    # Extract Base Version from Dockerfile (e.g., 8.11.0)
    local version=$(grep '^FROM' "$dockerfile" | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')
    version=${version:-latest}
    
    local tag_suffix="${current_hash:0:7}"
    local tag="$BASE_REPO/$component:$version-$tag_suffix"
    
    if [ "$current_hash" == "$last_hash" ]; then
        echo "✅ [$component] Up to date (Hash: $tag_suffix). Skipping build."
    else
        echo "🔨 [$component] Building new image: $tag"
        
        # Build Command
        if [ -S "$BK_SOCK" ] || ensure_buildkit_running; then
            OUTPUT_OPTS="type=image,name=$tag,push=true"
            [[ "${REGISTRY_INSECURE:-false}" == "true" ]] && OUTPUT_OPTS="$OUTPUT_OPTS,registry.insecure=true"
            
            buildctl --addr "unix://$BK_SOCK" build \
                --frontend=dockerfile.v0 \
                --local context="$context" \
                --local dockerfile="$context" \
                --output "$OUTPUT_OPTS"
        else
            echo "   Docker Buildx fallback..."
            docker buildx build "$context" --platform linux/amd64,linux/arm64 -t "$tag" --push
        fi
        
        # Update Hash File
        if grep -q "^$component=" "$HASH_FILE"; then
            sed -i "s|^$component=.*|$component=$current_hash|" "$HASH_FILE"
        else
            echo "$component=$current_hash" >> "$HASH_FILE"
        fi
        echo "✅ [$component] Build Success."
    fi
    
    # Update YAML manifest to use new tag
    local yaml_file="${component}.yaml"
    # Mapping for corner cases
    if [ "$component" == "ingress" ]; then yaml_file="kibana-ingress.yaml"; fi # Just in case
    
    if [ -f "$yaml_file" ]; then
        echo "📝 Updating $yaml_file..."
        # Regex to replace 'image: ...' regardless if it was official or custom before
        # We match 'image: .*' inside the container spec. 
        # WARNING: This is naive sed. Ideally utilize yq, but sed is faster/standard here.
        # We look for lines containing 'image:' and having 'elasticsearch', 'logstash', etc context if possible, 
        # or just rely on the fact that ECK CRDs usually have one main image.
        
        # We use a pattern that matches standard image definitions
        # Assuming the YAML structure follows basic indentation
        
        # For ECK, image is often at spec.image or spec.podTemplate.spec.containers[0].image
        # We replace ANY occurence of image references for this component if strictly identified?
        # A safer bet matches the component name in the image string OR strictly matches 'image:'.
        
        # Let's replace ANY 'image: .*' with the new tag IF the file is dedicated to that component.
        # Since we have elasticsearch.yaml, logstash.yaml, etc., this is reasonably safe.
        sed -i "s|image: .*|image: $tag|g" "$yaml_file"
    else
        echo "⚠️  YAML file $yaml_file not found. Skipping update."
    fi
}

echo "🚀 Starting Smart Build for Elastic Stack..."
for comp in "${COMPONENTS[@]}"; do
    build_image "$comp"
done
echo "🎉 All builds processed."

# ────────────────────────────────────────────────
# Cache Cleanup (User Request: auto-prune > 2h)
echo "🧹 Cleaning Build Cache (>2h retention)..."
if [ -S "$BK_SOCK" ] || ensure_buildkit_running; then
    # BuildKit Prune
    buildctl --addr "unix://$BK_SOCK" prune --keep-duration 2h
    echo "✅ BuildKit cache pruned."
elif command -v docker >/dev/null 2>&1; then
    # Docker Buildx Prune
    docker buildx prune -f --filter "until=2h"
    echo "✅ Docker Buildx cache pruned."
fi
