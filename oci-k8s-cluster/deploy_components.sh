#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ────────────────────────────────────────────────
# Load shared helpers
source "$(dirname "$0")/common.sh"

COMPONENTS_DIR="$(dirname "$0")/../components"
REMOTE_BASE="/home/ubuntu/deployments"

# default: automatically tunnel detected ingress ports
TUNNEL_MODE="auto"
if [[ "${1:-}" == "--suggest-only" ]]; then
  TUNNEL_MODE="suggest"
  shift
fi

# ────────────────────────────────────────────────
# List all component directories
list_components() {
  find "$COMPONENTS_DIR" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort
}

# ────────────────────────────────────────────────
# Prompt user to select components (supports gum)
prompt_components() {
  mapfile -t components < <(list_components)
  if command -v gum >/dev/null 2>&1; then
    echo "📦 Select components to deploy (SPACE = toggle, ENTER to confirm):" >&2
    mapfile -t selected < <(gum choose --no-limit "${components[@]}")
  else
    echo "📦 Available components:" >&2
    for i in "${!components[@]}"; do
      printf "  [%d] %s\n" "$((i+1))" "${components[$i]}" >&2
    done
    echo >&2
    read -rp "Enter numbers (comma-separated) or ENTER for all: " choice
    if [[ -z "${choice:-}" ]]; then
      selected=("${components[@]}")
    else
      selected=()
      IFS=',' read -ra nums <<<"$choice"
      for n in "${nums[@]}"; do
        n="${n//[!0-9]/}"
        (( n>=1 && n<=${#components[@]} )) || { echo "⚠️ Invalid index '$n' ignored." >&2; continue; }
        selected+=("${components[$((n-1))]}")
      done
    fi
  fi

  if [[ "${#selected[@]}" -eq 0 ]]; then
    echo "🚫 No components selected." >&2
    exit 1
  fi

  # Only print the selected component names to stdout
  printf "%s\n" "${selected[@]}"
}

# ────────────────────────────────────────────────
# Deploy a single component
deploy_component() {
  local name="$1"
  local src="$COMPONENTS_DIR/$name"

  log_node "$MASTER_NODE" "🚀 Deploying component '$name'"

  # ensure clean remote dir
  run_remote "$MASTER_NODE" "mkdir -p '$REMOTE_BASE/$name' && rm -rf '$REMOTE_BASE/$name'/*"
  scp_to_remote "$MASTER_NODE" "$src" "$REMOTE_BASE/"

  # capture namespace (ignore remote prefixes)
  ns=$(
    run_remote_stream "$MASTER_NODE" \
      "bash --norc --noprofile -eu -o pipefail -c 'cat > /tmp/deploy_component.sh && bash --norc --noprofile /tmp/deploy_component.sh && rm -f /tmp/deploy_component.sh'" <<EOF \
    | tee /tmp/deploy_${name}.log \
    | sed -E 's/^\[[^]]+\] //' \
    | awk '/📦 Using namespace:/ {print $NF}' \
    | tail -n1
  #!/usr/bin/env bash
  set -euo pipefail
  
  cd "$REMOTE_BASE/$name"
  echo "📁 Working in: \$(pwd)"
  
  if [ -f ./commands.sh ]; then
    echo "▶ Running commands.sh..."
    chmod +x ./commands.sh
    ./commands.sh || echo "⚠️ commands.sh exited non-zero."
  fi
  
  if ls *.yaml >/dev/null 2>&1; then
    echo "⚙️ Applying YAML manifests..."
    kubectl apply -f . || echo "⚠️ Some manifests failed to apply."
  
    echo
    echo "🔍 Detecting created objects..."
    ns=\$(grep -h 'namespace:' *.yaml | awk '{print \$2}' | sort -u | head -n1)
    ns=\${ns:-default}
    echo "📦 Using namespace: \$ns"
    echo
  
    echo "🌐 Ingresses configured:"
    if kubectl -n "\$ns" get ingress -o json >/tmp/ing.json 2>/dev/null; then
      jq -r '
        if (.items|length)==0 then
          "  (none)"
        else
          .items[] |
            (.metadata.name // "no-name") as \$name |
            (.spec.rules // [])[]? |
            "  • " + (.host // "no-host") +
            " [" + \$name + "] -> " +
            ((.http.paths[]?.backend.service.name // "?") + ":" +
             ((.http.paths[]?.backend.service.port.number // "?")|tostring))
        end' /tmp/ing.json || echo "  (jq not installed)"
    else
      echo "  (none)"
    fi
  
    echo
    echo "🧩 Service ports exposed:"
    kubectl -n "\$ns" get svc -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,PORTS:.spec.ports[*].port --no-headers 2>/dev/null | awk '{print "  • "\$1" ("\$2") -> "\$3}' || echo "  (none)"
  else
    echo "ℹ️ No YAML manifests found."
  fi
  
  echo "✅ Component $name deployment complete."
EOF
)

  echo "🧠 [debug] detected namespace='$ns'"

echo
echo "🔌 Tunnel setup (namespace: $ns):"

if [[ "$TUNNEL_MODE" != "off" && -n "$ns" ]]; then
  echo "🔍 Detecting ingresses and services remotely..."
  
  # Run checks visibly (streamed)
  run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail" <<RMT
ns="$ns"
echo
echo "📡 Checking ingresses..."
kubectl -n "\$ns" get ingress -o wide || echo "  (no ingresses found)"

echo
echo "📡 Checking services..."
kubectl -n "\$ns" get svc -o wide || echo "  (no services found)"
RMT

  echo
  echo "🔍 Extracting ingress backends for namespace '$ns'..."

  ingress_backends=$(
    run_remote "$MASTER_NODE" "bash -eu -o pipefail" <<RMT 2>&1 \
    | sed -E 's/^\[[^]]+\] //' \
    | grep -E '^[a-zA-Z0-9._-]+:[0-9]+$' \
    | tr -d '\r'
ns="$ns"
set -x
echo "💾 Dumping ingress JSON for debugging..."
kubectl -n "\$ns" get ingress -o json | tee /tmp/ingress_\$ns.json | jq '.items | length'

echo "🔎 Extracting backends via jq..."
kubectl -n "\$ns" get ingress -o json 2>/dev/null | jq -r '
  .items[]? | .spec.rules[]?.http.paths[]? |
  (.backend.service.name + ":" + ((.backend.service.port.number|tostring)//""))' || true
set +x
RMT
  ) || true

  echo
  echo "🧠 [debug] ingress_backends captured (raw):"
  echo "$ingress_backends"
  echo

  echo
  if [[ -n "$ingress_backends" ]]; then
    echo "🌐 Ingress backend targets detected:"
    while IFS=: read -r svc port; do
      [[ -z "$svc" || -z "$port" ]] && continue
      echo "  • $svc:$port"
      if [[ "$TUNNEL_MODE" == "auto" ]]; then
        kill_local_tunnel "$port"
        ssh -f -i "$SSH_KEY" -L "$port:10.0.1.100:$port" "ubuntu@$MASTER_PUBLIC_IP" -N \
          && echo "    ✅ Tunnel established: https://localhost:$port/"
      else
        echo "    💡 Suggestion: ssh -i \$SSH_KEY -L $port:10.0.1.100:$port ubuntu@$MASTER_PUBLIC_IP -N"
      fi
    done <<<"$ingress_backends"
  else
    echo "  (no ingress backends detected)"
  fi
else
  echo "  ⚠️ No namespace detected; skipping tunnel setup."
fi
}

# ────────────────────────────────────────────────
# Deploy all or selected components
deploy_selected() {
  local -a comps=("$@")
  for comp in "${comps[@]}"; do
    deploy_component "$comp"
  done
}

# ────────────────────────────────────────────────
# Main
main() {
  local -a selection
  if [[ $# -gt 0 ]]; then
    selection=("$@")
  else
    mapfile -t selection < <(prompt_components)
  fi
  deploy_selected "${selection[@]}"
}

main "$@"