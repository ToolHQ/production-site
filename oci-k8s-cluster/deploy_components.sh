#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ────────────────────────────────────────────────
# Load shared helpers
source "$(dirname "$0")/common.sh"
source "$(dirname "$0")/lib/credstore.sh"

COMPONENTS_DIR="$(dirname "$0")/../components"
REMOTE_BASE="/home/ubuntu/deployments"

# default: automatically tunnel detected ingress ports
# default: suggest only (do not automatically open ssh tunnels)
TUNNEL_MODE="suggest"
if [[ "${1:-}" == "--auto-tunnel" ]]; then
  TUNNEL_MODE="auto"
  shift
fi

# ────────────────────────────────────────────────
# List deployable component directories (skip archived / internal prefixes)
list_components() {
  find "$COMPONENTS_DIR" -mindepth 1 -maxdepth 1 -type d \
    ! -name '_*' ! -name '.*' \
    -printf "%f\n" | sort
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
# Detect namespace from YAMLs inside a remote component directory
detect_namespace() {
  local component="$1"
  local detected_ns

  detected_ns=$(
    run_remote_raw "$MASTER_NODE" "grep -h -m1 'namespace:' /home/ubuntu/deployments/$component/*.yaml 2>/dev/null | awk '{print \$2}'" |
      sed -E 's/.*]//' |                      # remove possible leading garbage
      grep -E '^[A-Za-z0-9._-]+$' |          # keep only valid names
      tail -n 1 | tr -d '\r[:space:]'        # cleanup CRs and spaces
  )

  if [[ -z "$detected_ns" ]]; then
    detected_ns="$component"
  fi

  echo "$detected_ns"
}

# Apply manifests remotely
apply_component_manifests() {
  local component="$1"
  log_node "$MASTER_NODE" "📦 Applying manifests for component '$component'"

  # Fetch Nexus credentials locally
  local cred_json
  cred_json=$(credstore_get_credential "nexus-admin" 2>/dev/null || echo "{}")
  local nexus_pass
  nexus_pass=$(echo "$cred_json" | jq -r '.password')

  # Special handling for Postgres Coroot Credential (local generation)
  local coroot_pg_pass=""
  local pg_rep_pass=""
  if [[ "$component" == "postgres" ]]; then
    # Replication Password (Early Generation)
    local cred_rep="postgres_replication_password"
    local cred_json_rep=$(credstore_get_credential "$cred_rep" 2>/dev/null || echo "{}")
    local pg_rep_pass=""
    
    if [ -z "$cred_json_rep" ] || [ "$cred_json_rep" = "{}" ]; then
         echo "🆕 Generating new secure password for Postgres Replication..."
         pg_rep_pass=$(openssl rand -base64 24)
         credstore_add "$cred_rep" "replicator" "$pg_rep_pass" "Postgres replication user"
    else
         pg_rep_pass=$(echo "$cred_json_rep" | jq -r '.password')
         echo "🔑 Using existing Replication credential from local store."
    fi

    # Coroot Credential
      local cred_name="postgres_coroot_password"
      local cred_json_pg=$(credstore_get_credential "$cred_name" 2>/dev/null || echo "{}")
      
      if [[ "$cred_json_pg" == "{}" ]]; then
           echo "🆕 Generating new secure password for Coroot Postgres integration..."
           coroot_pg_pass=$(openssl rand -base64 18)
           credstore_add "$cred_name" "coroot" "$coroot_pg_pass" "Postgres user for Coroot metrics"
      else
           coroot_pg_pass=$(echo "$cred_json_pg" | jq -r '.password')
           echo "🔑 Using existing Coroot Postgres credential from local store."
      fi
  fi

  run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail" <<RMT
# Inject host IP for registry access (fixes 'connection refused' on 127.0.0.1)
# We try to use the Nexus Pod IP directly to bypass potential kube-proxy/NodePort issues on the master
NEXUS_POD_IP=\$(kubectl get pods -n nexus -l app=nexus -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)

if [[ -n "\$NEXUS_POD_IP" ]]; then
  export DOCKER_REGISTRY_HOST="\$NEXUS_POD_IP"
  export PORT=18444
  echo "🔌 Registry (Pod Direct): \$DOCKER_REGISTRY_HOST:\$PORT"
else
  export DOCKER_REGISTRY_HOST=\$(hostname -I | awk '{print \$1}')
  export PORT=31444
  echo "🔌 Registry (Node LAN): \$DOCKER_REGISTRY_HOST:\$PORT"
fi

# Detect if registry is HTTP (insecure)
if curl --connect-timeout 2 -s -I "http://\$DOCKER_REGISTRY_HOST:\$PORT/v2/" >/dev/null 2>&1 || \
   curl --connect-timeout 2 -s -I "http://\$DOCKER_REGISTRY_HOST:\$PORT/" >/dev/null 2>&1; then
  export REGISTRY_INSECURE=true
  echo "🔓 Registry detected as HTTP (Insecure)"
else
  export REGISTRY_INSECURE=false
  echo "🔒 Registry detected as HTTPS (Secure) or unreachable via HTTP"
fi

# Configure Registry Credentials
NEXUS_PASS="$nexus_pass"
COROOT_PG_PASSWORD="$coroot_pg_pass"
export COROOT_PG_PASSWORD

if [[ -n "\$NEXUS_PASS" && "\$NEXUS_PASS" != "null" ]]; then
  echo "🔐 Configuring registry credentials for user 'admin'..."
  mkdir -p ~/.docker
  
  # Create auth string (admin:password) base64 encoded
  AUTH_STR=\$(echo -n "admin:\$NEXUS_PASS" | base64 -w0)
  
  # Write config.json
  cat > ~/.docker/config.json <<EOF
{
	"auths": {
		"\$DOCKER_REGISTRY_HOST:\$PORT": {
			"auth": "\$AUTH_STR"
		},
		"registry.local:31444": {
			"auth": "\$AUTH_STR"
		}
	}
}
EOF
  echo "✓ Credentials configured in ~/.docker/config.json"
else
  echo "⚠️  No Nexus admin password found. Push may fail if auth is required."
fi

cd /home/ubuntu/deployments/$component
if [ -f commands.sh ]; then
  chmod +x commands.sh
  echo "▶ Running custom commands.sh for $component..."
  NEXUS_PASS="$nexus_pass" COROOT_PG_PASSWORD="$coroot_pg_pass" PG_REP_PASS="$pg_rep_pass" ./commands.sh
else
  echo "▶ Applying YAML manifests in $component..."
  kubectl apply -f .
fi
RMT
}

# Step 3-A: Inspect services and capture structured data
inspect_services() {
  local ns="$1"
  run_remote "$MASTER_NODE" "kubectl -n $ns get svc -o json" 2>/dev/null
}

# Step 3-B: Inspect ingresses and capture structured data
inspect_ingresses() {
  local ns="$1"
  run_remote "$MASTER_NODE" "kubectl -n $ns get ingress -o json" 2>/dev/null
}

# Step 3: Display + assign results to local variables
inspect_component_resources() {
  local ns="$1"
  log_node "$MASTER_NODE" "🔍 Collecting resources in namespace '$ns'"

  run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail" <<RMT
echo "📦 Workloads (Deploy/STS/DS/CronJob):"
kubectl -n "$ns" get deploy,sts,ds,cronjob -o wide 2>/dev/null || echo "  (none)"
echo
echo "🧩 Services:"
kubectl -n "$ns" get svc -o wide 2>/dev/null || echo "  (none)"
echo
echo "🌐 Ingresses:"
kubectl -n "$ns" get ingress -o wide 2>/dev/null || echo "  (none)"
RMT
}

prepare_tunnel_targets() {
  local ns="$1"
  local services_json="$2"
  local ingresses_json="$3"
  local node_ip="${MASTER_NODE_IP:-10.0.1.100}"

  echo "🔧 Preparing tunnel targets for namespace '$ns'"

  # Use global scope arrays (not local) to persist values
  service_tunnels=()
  ingress_tunnels=()

  # --- Parse Services ---
  if jq -e . >/dev/null 2>&1 <<<"$services_json"; then
    local svc_count
    svc_count=$(jq '.items | length' <<<"$services_json")
    if (( svc_count > 0 )); then
      echo "🧩 Found $svc_count service(s):"
      while IFS=$'\t' read -r svc_name svc_type svc_ports svc_nodeports; do
        [[ -z "$svc_name" || -z "$svc_ports" ]] && continue
        echo "   • $svc_name ($svc_type) ports: $svc_ports${svc_nodeports:+ / nodePorts:$svc_nodeports}"

        # --- Use NodePorts if available and service type is NodePort ---
        if [[ "$svc_type" == "NodePort" && -n "$svc_nodeports" ]]; then
          IFS=',' read -ra np_ports <<<"$svc_nodeports"
          for np in "${np_ports[@]}"; do
            [[ "$np" =~ ^[0-9]+$ ]] || continue
            service_tunnels+=( "${np}:${node_ip}:${np}" )
          done
        else
          IFS=',' read -ra ports <<<"$svc_ports"
          for p in "${ports[@]}"; do
            [[ "$p" =~ ^[0-9]+$ ]] || continue
            service_tunnels+=( "${p}:${node_ip}:${p}" )
          done
        fi
      done < <(
        jq -r '
          .items[]
          | .metadata.name as $name
          | .spec.type as $type
          | ([.spec.ports[]? | .port] | map(tostring) | join(",")) as $ports
          | ([.spec.ports[]? | .nodePort // empty] | map(tostring) | join(",")) as $nodes
          | [$name, $type, $ports, $nodes]
          | @tsv
        ' <<<"$services_json"
      )
    fi
  fi

  # --- Parse Ingresses ---
  if jq -e . >/dev/null 2>&1 <<<"$ingresses_json"; then
    local ing_count
    ing_count=$(jq '.items | length' <<<"$ingresses_json")
    if (( ing_count > 0 )); then
      echo "🌐 Found $ing_count ingress(es):"
      while IFS=$'\t' read -r ing_name ing_hosts ing_port; do
        [[ -z "$ing_name" || -z "$ing_port" ]] && continue
        echo "   • $ing_name host(s): $ing_hosts port:$ing_port"
        ingress_tunnels+=( "8080:${node_ip}:${ing_port}" )
      done < <(
        jq -r '
          .items[]
          | .metadata.name as $name
          | ([.spec.rules[].host] | join(",")) as $hosts
          | (.spec.rules[].http.paths[].backend.service.port.number // 80) as $port
          | [$name, $hosts, ($port|tostring)]
          | @tsv
        ' <<<"$ingresses_json"
      )
    fi
  fi

  # --- INGRESS-FIRST POLICY ---
  # If we have Ingress tunnels, ignore Service/NodePort tunnels to reduce noise and resource usage.
  if (( ${#ingress_tunnels[@]} > 0 )); then
      echo "✨ Ingress validated. Skipping bare Service tunnels (Ingress-First Policy)."
      service_tunnels=()
  fi

  export service_tunnels ingress_tunnels
}


# Step 4: Establish tunnels automatically
establish_tunnels() {
  local namespace="$1"
  local tunnels=("${service_tunnels[@]}" "${ingress_tunnels[@]}")
  local ssh_key="${SSH_KEY}"
  local master_ip="${MASTER_PUBLIC_IP}"
  local pid

  # declare associative array early to avoid unbound-variable errors
  declare -A used_ports=()

  echo "🔌 Establishing SSH tunnels for namespace '$namespace'…"

  if ((${#tunnels[@]} == 0)); then
    echo "⚠️  No tunnel targets detected for '$namespace'."
    return 0
  fi

  if [[ "$TUNNEL_MODE" == "suggest" ]]; then
      echo "ℹ️  Skipping auto-tunnel (Mode: Suggest). Use 'Access & Port Forwarding' menu to connect."
      return 0
  fi

  for t in "${tunnels[@]}"; do
    IFS=':' read -r lport rhost rport <<<"$t"
    [[ -z "$lport" || -z "$rport" ]] && continue

    # Skip reserved Dashboard port
    if [[ "$lport" -eq 8443 ]]; then
      echo "🛡️  Skipping reserved port 8443 (Dashboard tunnel)"
      continue
    fi

    # Find next free port if needed
    while lsof -iTCP:"$lport" -sTCP:LISTEN -t >/dev/null 2>&1 || [[ -n "${used_ports[$lport]:-}" ]]; do
      ((lport++))
    done
    used_ports["$lport"]=1

    echo "🔗  Forwarding localhost:$lport → $rhost:$rport"
    ssh -f -N -i "$ssh_key" \
        -L "${lport}:${rhost}:${rport}" \
        -o StrictHostKeyChecking=no -o ConnectTimeout=3 \
        "ubuntu@${master_ip}" >/dev/null 2>&1 &
    pid=$!

    if ps -p "$pid" >/dev/null 2>&1; then
      echo "✅ Tunnel established (pid $pid) → localhost:$lport → $rhost:$rport"
    else
      echo "❌ Failed to establish tunnel for $rhost:$rport"
    fi
  done

  echo "🧭 Active localhost forwards:"
  for p in "${!used_ports[@]}"; do
    local scheme="http"
    # Guess HTTPS ports
    if [[ "$p" -eq 443 || "$p" -eq 8443 || ( "$p" -ge 9443 && "$p" -lt 9500 ) ]]; then
      scheme="https"
    fi
    echo "   • ${scheme}://localhost:${p}"
  done
}

# Deploy a single component
deploy_component() {
  local component="$1"
  local ns=""
  local ingress_backends=""
  local nodeports=""

  if [[ "$component" == "ssdnodes" ]]; then
    echo "❌ components/ssdnodes é exclusivo do cluster SSDNodes (ssdnodes-6a12f10c9ef11)." >&2
    echo "   Use: bash oci-k8s-cluster/scripts/ssdnodes/deploy_ssdnodes_components.sh ci-platform" >&2
    echo "   Ou TUI → Node Hardening → SSDNodes CI (T-341)" >&2
    return 1
  fi

  log_node "$MASTER_NODE" "🚀 Syncing tools to master node"
  run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail" <<RMT
mkdir -p '/home/ubuntu/tools'
RMT
  scp_to_remote "$MASTER_NODE" "./../tools" "/home/ubuntu/"

  log_node "$MASTER_NODE" "🚀 Deploying component '$component'"
  run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail" <<RMT
mkdir -p '/home/ubuntu/deployments/$component' && rm -rf '/home/ubuntu/deployments/$component'/*
RMT

  scp_to_remote "$MASTER_NODE" "./../components/$component" "/home/ubuntu/deployments/"

  # 1. Detect the namespace used by the component YAMLs.
  ns=$(detect_namespace "$component")
  echo "🧠 [debug] detected namespace='$ns'"

  # 2. Apply manifests remotely.
  apply_component_manifests "$component"

  # 3. Display + capture resource info
  inspect_component_resources "$ns"
  services_json=$(inspect_services "$ns")
  ingresses_json=$(inspect_ingresses "$ns")
  # --- Sanitize remote JSON ---
  # Remove lines that don't start with '{' or '[' and drop bracketed log prefixes
  services_json_clean="$(echo "$services_json" | sed -E 's/^\[[^]]*\]\s*//g' | awk '/^[ \t]*[{[]/{p=1} p' | tr -d '\r')"
  ingresses_json_clean="$(echo "$ingresses_json" | sed -E 's/^\[[^]]*\]\s*//g' | awk '/^[ \t]*[{[]/{p=1} p' | tr -d '\r')"

  # --- Improved debug summary ---
  if command -v jq >/dev/null 2>&1 \
     && jq -e . >/dev/null 2>&1 <<<"$services_json_clean" \
     && jq -e . >/dev/null 2>&1 <<<"$ingresses_json_clean"; then

    svc_count=$(jq '.items | length' <<<"$services_json_clean")
    ing_count=$(jq '.items | length' <<<"$ingresses_json_clean")
    svc_names=$(jq -r '.items[].metadata.name' <<<"$services_json_clean" | head -n 3 | paste -sd, -)
    ing_names=$(jq -r '.items[].metadata.name' <<<"$ingresses_json_clean" | head -n 3 | paste -sd, -)

    echo "🧠 [debug] Services ($svc_count): ${svc_names:-none}"
    echo "🧠 [debug] Ingresses ($ing_count): ${ing_names:-none}"
  else
    echo "🧠 [debug] JSON malformed or jq unavailable."
    echo "🧠 [debug] Raw lengths — services: ${#services_json_clean}B, ingresses: ${#ingresses_json_clean}B"
  fi
  # Prepare tunnel targets
  prepare_tunnel_targets "$ns" "$services_json_clean" "$ingresses_json_clean"
  echo "🧠 [debug] service_tunnels: ${#service_tunnels[@]} (${service_tunnels[*]:-none})"
  echo "🧠 [debug] ingress_tunnels: ${#ingress_tunnels[@]} (${ingress_tunnels[*]:-none})"

  # 4. Prepare tunnel setup.
  establish_tunnels "$ns"
  #    - Before creating any tunnel, close existing ones on overlapping local ports (kill_local_tunnel).
  #    - Ensure MASTER_PUBLIC_IP is available for ssh -L.
  #    - If ingress_backends exist:
  #         • For each backend, forward local port:<clusterIP>:<port>.
  #         • Log each established tunnel.
  #    - Else, if nodeports exist:
  #         • Detect one node’s InternalIP.
  #         • Forward <nodePort> to localhost:<nodePort>.
  #         • Log each established tunnel.

  # 5. Final logging and summary.
  #    - Print a clean summary:
  #         "✅ Component '$component' deployed in namespace '$ns'."
  #         "🌐 Forwarded ingress backends:" or "🌐 Forwarded NodePorts:"
  #    - Ensure output is concise and clear.

  # --- Special Post-Deploy Actions ---
  # (elastic-stack retired — see components/_archived/elastic-stack/README.md)
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
# Uninstall a single component
uninstall_component() {
  local component="$1"
  local ns=""

  log_node "$MASTER_NODE" "🗑️  Uninstalling component '$component'"

  # 1. Check for custom uninstall script
  local uninstall_script="./../components/$component/uninstall_commands.sh"
  
  # We need to copy it to remote to execute it there?
  # Actually, run_remote_stream allows executing local script content on remote via bash -s or similar?
  # Or we scp it.
  
  if [ -f "$uninstall_script" ]; then
      echo "▶ Found custom uninstall script. Executing on master..."
      scp_to_remote "$MASTER_NODE" "$uninstall_script" "/home/ubuntu/deployments/$component/uninstall_commands.sh"
      
      run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail" <<RMT
cd /home/ubuntu/deployments/$component
chmod +x uninstall_commands.sh
./uninstall_commands.sh
RMT
  else
      echo "▶ No custom uninstall script. Attempting standard 'kubectl delete -f .'..."
      # This assumes the deployments folder still exists on remote.
      run_remote_stream "$MASTER_NODE" "bash -eu -o pipefail" <<RMT
if [ -d "/home/ubuntu/deployments/$component" ]; then
    cd /home/ubuntu/deployments/$component
    kubectl delete -f . --ignore-not-found
else
    echo "⚠️  Deployment directory not found on remote. Skipping standard delete."
fi
RMT
  fi
  
  echo "✅ Component '$component' uninstalled."
}

# Uninstall selected components
uninstall_selected() {
  local -a comps=("$@")
  for comp in "${comps[@]}"; do
    uninstall_component "$comp"
  done
}


# ────────────────────────────────────────────────
# Main
main() {
  local mode="install"
  local -a selection=()

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --uninstall)
        mode="uninstall"
        shift
        ;;
      --auto-tunnel)
        TUNNEL_MODE="auto"
        shift
        ;;
      *)
        selection+=("$1")
        shift
        ;;
    esac
  done

  if [[ ${#selection[@]} -eq 0 ]]; then
    mapfile -t selection < <(prompt_components)
  fi

  if [[ "$mode" == "uninstall" ]]; then
      uninstall_selected "${selection[@]}"
  else
      deploy_selected "${selection[@]}"
  fi
}

main "$@"