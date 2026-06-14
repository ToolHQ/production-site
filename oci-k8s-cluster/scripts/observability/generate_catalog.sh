#!/bin/bash
# ------------------------------------------------------------------------------
# 📚 Unified Infrastructure Catalog & Inventory (T-110)
# ------------------------------------------------------------------------------
# Scans: apps/, components/, live cluster state
# Cross-references: repo ↔ cluster (deployed, pending, untracked, gaps)
# Output: JSON + Markdown + HTML
# ------------------------------------------------------------------------------

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
REPORT_ROOT="${REPO_ROOT}/reports"
MASTER_NODE="oci-k8s-master"
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
NOW_TS=$(date +%Y%m%d_%H%M%S)

OUTPUT_DIR="$REPORT_ROOT/catalog_${NOW_TS}"
mkdir -p "$OUTPUT_DIR"
TEMP_DIR=$(mktemp -d)
trap "rm -rf '$TEMP_DIR'" EXIT

CATALOG_JSON="$OUTPUT_DIR/catalog.json"
CATALOG_MD="$OUTPUT_DIR/catalog.md"
CATALOG_HTML="$OUTPUT_DIR/catalog.html"

# Colors (for terminal output during generation)
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

CLUSTER_ONLINE=false

# ==============================================================================
# PHASE 1A: SCAN APPS
# ==============================================================================
scan_apps() {
    echo -e "${BLUE}📦 Scanning apps/...${NC}"
    local apps_dir="$REPO_ROOT/apps"
    local json_arr="["
    local first=true

    for app_dir in "$apps_dir"/*/; do
        [ ! -d "$app_dir" ] && continue
        local name=$(basename "$app_dir")

        # Skip non-service dirs
        [[ "$name" == "data" || "$name" == "testing" || "$name" == "cluster-id" ]] && {
            continue
        }

        local language="unknown" framework="" version="" base_image=""
        local has_dockerfile=false has_k8s=false has_deploy=false has_readme=false has_commands=false
        local k8s_kinds="" deploy_script="" description="" key_deps=""

        # --- Language & Version Detection ---
        if [[ -f "$app_dir/package.json" ]]; then
            language="nodejs"
            version=$(jq -r '.version // "unknown"' "$app_dir/package.json" 2>/dev/null)
            local deps=$(jq -r '(.dependencies // {}) | keys[]' "$app_dir/package.json" 2>/dev/null || true)
            # Framework
            echo "$deps" | grep -q "^express$"    && framework="Express"
            echo "$deps" | grep -q "^fastify$"    && framework="Fastify"
            echo "$deps" | grep -q "^@nestjs"     && framework="NestJS"
            echo "$deps" | grep -q "^react$"      && framework="React"
            echo "$deps" | grep -q "^react-dom$"  && [[ -z "$framework" ]] && framework="React"
            echo "$deps" | grep -q "^vue$"        && framework="Vue"
            # Key deps (first 5)
            key_deps=$(echo "$deps" | head -5 | tr '\n' ', ' | sed 's/,$//')
            # Description
            description=$(jq -r '.description // ""' "$app_dir/package.json" 2>/dev/null)
        elif [[ -f "$app_dir/Cargo.toml" ]]; then
            language="rust"
            version=$(grep -m1 '^version' "$app_dir/Cargo.toml" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' || echo "unknown")
            local cargo_deps=$(grep -A999 '^\[dependencies\]' "$app_dir/Cargo.toml" 2>/dev/null | grep -E '^[a-z]' | head -10 | cut -d= -f1 | tr -d ' ')
            echo "$cargo_deps" | grep -q "^axum$"      && framework="Axum"
            echo "$cargo_deps" | grep -q "^actix-web$"  && framework="Actix-Web"
            echo "$cargo_deps" | grep -q "^rocket$"     && framework="Rocket"
            echo "$cargo_deps" | grep -q "^bevy$"       && framework="Bevy"
            echo "$cargo_deps" | grep -q "^warp$"       && framework="Warp"
            key_deps=$(echo "$cargo_deps" | head -5 | tr '\n' ', ' | sed 's/,$//')
        elif [[ -f "$app_dir/requirements.txt" ]]; then
            language="python"
            local py_deps=$(grep -v '^#' "$app_dir/requirements.txt" 2>/dev/null | cut -d= -f1 | cut -d'>' -f1 | cut -d'<' -f1 | tr -d ' ')
            echo "$py_deps" | grep -qi "^fastapi$" && framework="FastAPI"
            echo "$py_deps" | grep -qi "^django$"  && framework="Django"
            echo "$py_deps" | grep -qi "^flask$"   && framework="Flask"
            key_deps=$(echo "$py_deps" | head -5 | tr '\n' ', ' | sed 's/,$//')
            # Version from setup.py or pyproject.toml
            [[ -f "$app_dir/pyproject.toml" ]] && version=$(grep -m1 '^version' "$app_dir/pyproject.toml" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/' || echo "unknown")
        elif [[ -f "$app_dir/go.mod" ]]; then
            language="go"
        elif [[ -f "$app_dir/nginx.conf" ]] || [[ -f "$app_dir/default.conf" ]]; then
            language="nginx"
            framework="Nginx"
        fi

        # --- Dockerfile ---
        local df_path=""
        if [[ -f "$app_dir/Dockerfile" ]]; then
            df_path="$app_dir/Dockerfile"
        elif [[ -f "$app_dir/docker/Dockerfile" ]]; then
            df_path="$app_dir/docker/Dockerfile"
        elif ls "$app_dir/Dockerfile"* &>/dev/null; then
            df_path=$(ls "$app_dir/Dockerfile"* | head -1)
        elif ls "$app_dir/docker/Dockerfile"* &>/dev/null; then
            df_path=$(ls "$app_dir/docker/Dockerfile"* | head -1)
        fi

        if [[ -n "$df_path" ]]; then
            has_dockerfile=true
            base_image=$(grep -m1 '^FROM' "$df_path" 2>/dev/null | awk '{print $2}' || true)
            # If multi-stage, get last FROM
            local last_from=$(grep '^FROM' "$df_path" 2>/dev/null | tail -1 | awk '{print $2}')
            [[ -n "$last_from" ]] && base_image="$last_from"
        fi

        # --- K8s Manifests ---
        local k8s_files=$(find "$app_dir" -name '*.yaml' -o -name '*.yml' 2>/dev/null | xargs grep -l '^kind:' 2>/dev/null || true)
        if [[ -n "$k8s_files" ]]; then
            has_k8s=true
            k8s_kinds=$(echo "$k8s_files" | xargs grep '^kind:' 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' ',' | sed 's/,$//')
        fi

        # --- Deploy script ---
        for ds in deploy.sh publish.sh; do
            if [[ -f "$app_dir/$ds" ]]; then
                has_deploy=true
                deploy_script="$ds"
                break
            fi
        done

        # --- Docs & automation ---
        [[ -f "$app_dir/README.md" ]] && has_readme=true
        [[ -f "$app_dir/commands.sh" ]] && has_commands=true

        # --- Exposed port (Dockerfile EXPOSE + K8s containerPort) ---
        local exposed_port=""
        if $has_dockerfile; then
            exposed_port=$(grep -i '^EXPOSE' "$app_dir/Dockerfile" 2>/dev/null | awk '{print $2}' | head -1 || true)
        fi
        if [[ -z "$exposed_port" ]] && $has_k8s; then
            exposed_port=$(find "$app_dir" -name '*.yaml' -o -name '*.yml' 2>/dev/null \
                | xargs grep -h 'containerPort:' 2>/dev/null | awk '{print $NF}' | head -1 || true)
        fi

        # --- Deploy Readiness (5-state semantic) ---
        local readiness="" readiness_missing=""
        local missing_parts=""
        $has_dockerfile || missing_parts+="dockerfile,"
        $has_k8s        || missing_parts+="k8s-manifest,"
        $has_deploy     || missing_parts+="deploy-script,"
        readiness_missing="${missing_parts%,}"

        if $has_dockerfile && $has_k8s && $has_deploy; then
            readiness="deployable"
        elif $has_dockerfile || $has_k8s; then
            readiness="partial"
        elif [[ "$language" == "unknown" ]]; then
            readiness="infra-only"
        else
            readiness="wip"
        fi
        # Note: "deployed" state is set later in cross_reference, stored in xref

        # --- Deploy command ---
        local deploy_cmd="" deploy_script_path=""
        if [[ -n "$deploy_script" ]]; then
            deploy_script_path="apps/$name/$deploy_script"
            deploy_cmd="cd apps/$name && bash $deploy_script"
        fi

        # --- Build JSON entry ---
        $first && first=false || json_arr+=","
        json_arr+=$(cat <<JEOF
{
  "name": "$name",
  "language": "$language",
  "framework": "$framework",
  "version": "$version",
  "key_deps": "$key_deps",
  "dockerfile": $has_dockerfile,
  "base_image": "$base_image",
  "k8s_manifests": $has_k8s,
  "k8s_kinds": "$k8s_kinds",
  "deploy_script": "$deploy_script",
  "deploy_cmd": "$deploy_cmd",
  "deploy_script_path": "$deploy_script_path",
  "has_readme": $has_readme,
  "has_commands_sh": $has_commands,
  "exposed_port": "$exposed_port",
  "deploy_readiness": "$readiness",
  "readiness_missing": "$readiness_missing",
  "description": $(echo "$description" | jq -Rs '.')
}
JEOF
)
        echo -e "  ${GREEN}✓${NC} $name ($language${framework:+/$framework} v${version})"
    done

    json_arr+="]"
    echo "$json_arr" | jq '.' > "$TEMP_DIR/apps.json"
}

# ==============================================================================
# PHASE 1B: SCAN COMPONENTS
# ==============================================================================
scan_components() {
    echo -e "${BLUE}⚙️  Scanning components/...${NC}"
    local comp_dir="$REPO_ROOT/components"
    local json_arr="["
    local first=true

    for c_dir in "$comp_dir"/*/; do
        [ ! -d "$c_dir" ] && continue
        local name=$(basename "$c_dir")
        # Skip archived / internal component trees
        [[ "$name" == _* ]] && continue

        local category="" namespace="" deploy_method="raw-manifest" comp_version=""
        local has_commands=false has_readme=false deprecated=false
        local k8s_kinds="" images="" storage_pvcs=""

        # --- Category Heuristic ---
        case "$name" in
            cilium|ingress-nginx|coredns)       category="networking" ;;
            longhorn|local-path-provisioner|storage|minio) category="storage" ;;
            coroot|clickhouse|observability*) category="observability" ;;
            cert-manager|actions|kube-system)    category="security" ;;
            postgres)                            category="database" ;;
            nexus)                               category="registry" ;;
            backup)                              category="backup" ;;
            kubernetes-dashboard|metrics-server) category="system" ;;
            kubecost)                            category="finops" ;;
            *)                                   category="other" ;;
        esac

        # --- Deprecated ---
        [[ "$name" == *deprecated* ]] && deprecated=true

        # --- Deploy Method ---
        if find "$c_dir" -maxdepth 1 -name 'values.yaml' -o -name '*-values.yaml' 2>/dev/null | grep -q .; then
            deploy_method="helm"
        fi

        # --- Scan YAML files ---
        local all_yamls=$(find "$c_dir" -name '*.yaml' -o -name '*.yml' 2>/dev/null || true)
        if [[ -n "$all_yamls" ]]; then
            # K8s kinds
            k8s_kinds=$(echo "$all_yamls" | xargs grep -h '^kind:' 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' ',' | sed 's/,$//' || true)

            # Namespace: prefer namespace of Deployment/StatefulSet/DaemonSet/CronJob
            namespace=$(echo "$all_yamls" | xargs grep -h -A8 'kind: Deployment\|kind: StatefulSet\|kind: DaemonSet\|kind: CronJob' 2>/dev/null \
                | grep 'namespace:' | awk '{print $2}' | grep -v '^$\|^default$' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' || true)
            # Fall back: most frequent non-default namespace across all files
            if [[ -z "$namespace" ]]; then
                namespace=$(echo "$all_yamls" | xargs grep -h 'namespace:' 2>/dev/null \
                    | awk '{print $2}' | grep -v '^$\|^default$' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' || true)
            fi
            [[ -z "$namespace" ]] && namespace="default"

            # Images
            images=$(echo "$all_yamls" | xargs grep -h 'image:' 2>/dev/null | grep -v '#' | sed 's/.*image:\s*//' | tr -d '"' | tr -d "'" | sort -u | head -10 | tr '\n' ',' | sed 's/,$//' || true)

            # Version from images or chart annotations
            if [[ -n "$images" ]]; then
                comp_version=$(echo "$images" | tr ',' '\n' | head -1 | grep -oP ':\K[^,]+$' || true)
                comp_version=${comp_version#v}  # strip leading v to avoid double-v later
            fi
            # Override with Helm chart version if available
            local chart_ver=$(echo "$all_yamls" | xargs grep -h 'app.kubernetes.io/version' 2>/dev/null | head -1 | sed 's/.*: *//' | tr -d '"' || true)
            [[ -n "$chart_ver" ]] && comp_version="${chart_ver#v}"

            # PVCs
            storage_pvcs=$(echo "$all_yamls" | xargs grep -A5 'kind: PersistentVolumeClaim' 2>/dev/null | grep 'storage:' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//' || true)
        fi

        # --- Files ---
        [[ -f "$c_dir/commands.sh" ]] && has_commands=true
        [[ -f "$c_dir/README.md" ]] && has_readme=true

        # --- Build JSON ---
        $first && first=false || json_arr+=","
        json_arr+=$(cat <<JEOF
{
  "name": "$name",
  "category": "$category",
  "namespace": "$namespace",
  "deploy_method": "$deploy_method",
  "version": "$comp_version",
  "images": "$images",
  "k8s_kinds": "$k8s_kinds",
  "has_commands_sh": $has_commands,
  "has_readme": $has_readme,
  "storage_pvcs": "$storage_pvcs",
  "deprecated": $deprecated
}
JEOF
)
        echo -e "  ${GREEN}✓${NC} $name ($category, $deploy_method${comp_version:+, v$comp_version})"
    done

    json_arr+="]"
    echo "$json_arr" | jq '.' > "$TEMP_DIR/components.json"
}

# ==============================================================================
# PHASE 2: SCAN CLUSTER (requires SSH tunnel)
# ==============================================================================
scan_cluster() {
    echo -e "${BLUE}☸️  Scanning live cluster via SSH ($MASTER_NODE)...${NC}"

    # Test connectivity
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$MASTER_NODE" "kubectl cluster-info" &>/dev/null; then
        echo -e "${YELLOW}⚠️  Cluster unreachable — skipping live scan (offline mode)${NC}"
        echo '[]' > "$TEMP_DIR/cluster_workloads.json"
        echo '[]' > "$TEMP_DIR/cluster_services.json"
        echo '[]' > "$TEMP_DIR/cluster_ingresses.json"
        CLUSTER_ONLINE=false
        return
    fi

    CLUSTER_ONLINE=true
    echo -e "  ${GREEN}✓${NC} Cluster reachable"

    # Single SSH session — fetch everything at once
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$MASTER_NODE" bash <<'REMOTE_EOF' > "$TEMP_DIR/cluster_raw.json"
set -e
echo '{"workloads":'
kubectl get deploy,sts,ds,cronjob -A -o json 2>/dev/null | jq '[.items[] | {
    kind: .kind,
    name: .metadata.name,
    namespace: .metadata.namespace,
    images: [.spec.template.spec.containers[]?.image // empty],
    replicas: (.spec.replicas // .status.desiredNumberScheduled // null),
    ready_replicas: (.status.readyReplicas // .status.numberReady // null),
    created: .metadata.creationTimestamp,
    generation: .metadata.generation
}]'
echo ',"services":'
kubectl get svc -A -o json 2>/dev/null | jq '[.items[] | {
    name: .metadata.name,
    namespace: .metadata.namespace,
    type: .spec.type,
    ports: [.spec.ports[]? | "\(.port)/\(.protocol // "TCP")"],
    cluster_ip: .spec.clusterIP
}]'
echo ',"ingresses":'
kubectl get ingress -A -o json 2>/dev/null | jq '[.items[] | {
    name: .metadata.name,
    namespace: .metadata.namespace,
    hosts: [.spec.rules[]?.host],
    tls: (.spec.tls != null)
}]'
echo ',"pods":'
kubectl get pods -A -o json 2>/dev/null | jq '[.items[] | {
    name: .metadata.name,
    namespace: .metadata.namespace,
    status: .status.phase,
    images: [.spec.containers[]?.image // empty],
    restarts: ([.status.containerStatuses[]?.restartCount // 0] | add // 0),
    ready: ((.status.containerStatuses // []) | map(select(.ready == true)) | length),
    total: ((.status.containerStatuses // []) | length),
    node: .spec.nodeName,
    started: .status.startTime
}]'
echo '}'
REMOTE_EOF

    # Validate and split
    if jq -e '.' "$TEMP_DIR/cluster_raw.json" &>/dev/null; then
        jq '.workloads'  "$TEMP_DIR/cluster_raw.json" > "$TEMP_DIR/cluster_workloads.json"
        jq '.services'   "$TEMP_DIR/cluster_raw.json" > "$TEMP_DIR/cluster_services.json"
        jq '.ingresses'  "$TEMP_DIR/cluster_raw.json" > "$TEMP_DIR/cluster_ingresses.json"
        jq '.pods'       "$TEMP_DIR/cluster_raw.json" > "$TEMP_DIR/cluster_pods.json"

        local wl_count=$(jq 'length' "$TEMP_DIR/cluster_workloads.json")
        local svc_count=$(jq 'length' "$TEMP_DIR/cluster_services.json")
        local pod_count=$(jq 'length' "$TEMP_DIR/cluster_pods.json")
        echo -e "  ${GREEN}✓${NC} Fetched: ${wl_count} workloads, ${svc_count} services, ${pod_count} pods"
    else
        echo -e "${RED}✗ Failed to parse cluster data — using empty state${NC}"
        echo '[]' > "$TEMP_DIR/cluster_workloads.json"
        echo '[]' > "$TEMP_DIR/cluster_services.json"
        echo '[]' > "$TEMP_DIR/cluster_ingresses.json"
        CLUSTER_ONLINE=false
    fi
}

# ==============================================================================
# PHASE 3: CROSS-REFERENCE ENGINE
# ==============================================================================
cross_reference() {
    echo -e "${BLUE}🔄 Building cross-reference...${NC}"

    # Extract cluster workload names+namespaces for matching
    local wl_names="$TEMP_DIR/wl_names.txt"
    jq -r '.[] | "\(.namespace)|\(.name)|\(.kind)|\((.images // [""])[0])"' \
        "$TEMP_DIR/cluster_workloads.json" > "$wl_names" 2>/dev/null || true

    # Init accumulator files
    echo '[]' > "$TEMP_DIR/xr_deployed.json"
    echo '[]' > "$TEMP_DIR/xr_repo_only_apps.json"
    echo '[]' > "$TEMP_DIR/xr_repo_only_comps.json"
    > "$TEMP_DIR/xr_matched_ns.txt"

    # --- Match apps to cluster ---
    for app_dir in "$REPO_ROOT/apps"/*/; do
        [ ! -d "$app_dir" ] && continue
        local app_name=$(basename "$app_dir")
        [[ "$app_name" == "data" || "$app_name" == "testing" || "$app_name" == "cluster-id" ]] && continue

        local app_json=$(jq --arg n "$app_name" '.[] | select(.name == $n)' "$TEMP_DIR/apps.json")
        local app_lang=$(echo "$app_json" | jq -r '.language')
        local app_readiness=$(echo "$app_json" | jq -r '.deploy_readiness')
        local app_framework=$(echo "$app_json" | jq -r '.framework // ""')

        # Find K8s manifest workload names
        local manifest_wl_names=$(find "$app_dir" -name '*.yaml' -o -name '*.yml' 2>/dev/null \
            | xargs grep -A1 '^kind: \(Deployment\|StatefulSet\|DaemonSet\)' 2>/dev/null \
            | grep 'name:' | head -3 | awk '{print $2}' || true)

        # Match: by manifest name, or by partial name match
        local match_lines=""
        for mn in $manifest_wl_names; do
            local found=$(grep -i "|${mn}|" "$wl_names" || true)
            [ -n "$found" ] && match_lines+="$found"$'\n'
        done
        # Fallback: match workload name that equals or starts with app_name
        if [ -z "$match_lines" ]; then
            match_lines=$(grep -iE "\|${app_name}\||\|${app_name}-" "$wl_names" || true)
        fi

        if [ -n "$match_lines" ] && [ "$CLUSTER_ONLINE" = "true" ]; then
            local cluster_wl_json=$(echo "$match_lines" | grep -v '^$' | cut -d'|' -f2 | sort -u | jq -R . | jq -s '.')
            local cluster_ns=$(echo "$match_lines" | grep -v '^$' | head -1 | cut -d'|' -f1)
            echo "$cluster_ns" >> "$TEMP_DIR/xr_matched_ns.txt"

            # Replica counts: sum ready/desired across all workloads in namespace
            local ready_r=$(jq --arg ns "$cluster_ns" \
                '[.[] | select(.namespace == $ns) | .ready_replicas // 0] | add // 0' \
                "$TEMP_DIR/cluster_workloads.json")
            local desired_r=$(jq --arg ns "$cluster_ns" \
                '[.[] | select(.namespace == $ns) | .replicas // 0] | add // 0' \
                "$TEMP_DIR/cluster_workloads.json")

            # Total restarts across pods in namespace
            local restarts=$(jq --arg ns "$cluster_ns" \
                '[.[] | select(.namespace == $ns) | .restarts // 0] | add // 0' \
                "$TEMP_DIR/cluster_pods.json")

            # Ingress hosts for this namespace
            local ingress_hosts_json=$(jq --arg ns "$cluster_ns" \
                '[.[] | select(.namespace == $ns) | .hosts[]] | unique' \
                "$TEMP_DIR/cluster_ingresses.json")

            # Drift: repo version vs cluster image tag
            local repo_ver=$(echo "$app_json" | jq -r '.version // ""')
            local cluster_img=$(echo "$match_lines" | grep -v '^$' | head -1 | cut -d'|' -f4)
            local cluster_tag="${cluster_img##*:}"
            local drift="unknown"
            if [[ -n "$repo_ver" && -n "$cluster_tag" && "$cluster_tag" != "latest" ]]; then
                [[ "$cluster_tag" == *"$repo_ver"* ]] && drift="in-sync" || drift="drift"
            fi

            jq --arg name "$app_name" --arg lang "$app_lang" --arg fw "$app_framework" \
                --argjson wl "$cluster_wl_json" --arg ns "$cluster_ns" \
                --argjson ready "$ready_r" --argjson desired "$desired_r" \
                --argjson restarts "$restarts" \
                --argjson ingress_hosts "$ingress_hosts_json" \
                --arg drift "$drift" --arg cluster_img "$cluster_img" \
                '. + [{source:"app", name:$name, language:$lang, framework:$fw,
                       cluster_workloads:$wl, cluster_namespace:$ns, status:"healthy",
                       replicas_ready:$ready, replicas_desired:$desired,
                       total_restarts:$restarts, ingress_hosts:$ingress_hosts,
                       cluster_image:$cluster_img, version_drift:$drift}]' \
                "$TEMP_DIR/xr_deployed.json" > "$TEMP_DIR/xr_deployed.tmp" \
                && mv "$TEMP_DIR/xr_deployed.tmp" "$TEMP_DIR/xr_deployed.json"
        else
            local app_missing=$(echo "$app_json" | jq -r '.readiness_missing // ""')
            jq --arg name "$app_name" --arg lang "$app_lang" \
                --arg readiness "$app_readiness" --arg missing "$app_missing" \
                '. + [{name:$name, language:$lang, readiness:$readiness, readiness_missing:$missing}]' \
                "$TEMP_DIR/xr_repo_only_apps.json" > "$TEMP_DIR/xr_roa.tmp" \
                && mv "$TEMP_DIR/xr_roa.tmp" "$TEMP_DIR/xr_repo_only_apps.json"
        fi
    done

    # --- Match components to cluster (by namespace) ---
    local comp_count=$(jq '. | length' "$TEMP_DIR/components.json")
    for i in $(seq 0 $(( comp_count - 1 ))); do
        local comp_json=$(jq ".[$i]" "$TEMP_DIR/components.json")
        local comp_name=$(echo "$comp_json" | jq -r '.name')
        local comp_ns=$(echo "$comp_json" | jq -r '.namespace // ""')
        local comp_cat=$(echo "$comp_json" | jq -r '.category')
        local comp_deprecated=$(echo "$comp_json" | jq -r '.deprecated')

        [ "$comp_deprecated" = "true" ] && continue

        # Determine effective namespace: prefer extracted ns, fall back to component name
        local effective_ns="$comp_ns"
        if [ "$CLUSTER_ONLINE" = "true" ]; then
            # If extracted ns is empty/default, or doesn't match cluster, try component name as ns
            if [[ -z "$effective_ns" || "$effective_ns" == "default" ]] || ! grep -q "^${effective_ns}|" "$wl_names" 2>/dev/null; then
                if grep -q "^${comp_name}|" "$wl_names" 2>/dev/null; then
                    effective_ns="$comp_name"
                fi
            fi
        fi

        if [ -n "$effective_ns" ] && grep -q "^${effective_ns}|" "$wl_names" 2>/dev/null && [ "$CLUSTER_ONLINE" = "true" ]; then
            local cluster_wl_json=$(grep "^${effective_ns}|" "$wl_names" | cut -d'|' -f2 | sort -u | jq -R . | jq -s '.')
            echo "$effective_ns" >> "$TEMP_DIR/xr_matched_ns.txt"

            local c_ready_r=$(jq --arg ns "$effective_ns" \
                '[.[] | select(.namespace == $ns) | .ready_replicas // 0] | add // 0' \
                "$TEMP_DIR/cluster_workloads.json")
            local c_desired_r=$(jq --arg ns "$effective_ns" \
                '[.[] | select(.namespace == $ns) | .replicas // 0] | add // 0' \
                "$TEMP_DIR/cluster_workloads.json")
            local c_restarts=$(jq --arg ns "$effective_ns" \
                '[.[] | select(.namespace == $ns) | .restarts // 0] | add // 0' \
                "$TEMP_DIR/cluster_pods.json")
            local c_ing_hosts=$(jq --arg ns "$effective_ns" \
                '[.[] | select(.namespace == $ns) | .hosts[]] | unique' \
                "$TEMP_DIR/cluster_ingresses.json")

            jq --arg name "$comp_name" --arg cat "$comp_cat" --arg ns "$effective_ns" \
                --argjson wl "$cluster_wl_json" \
                --argjson ready "$c_ready_r" --argjson desired "$c_desired_r" \
                --argjson restarts "$c_restarts" \
                --argjson ingress_hosts "$c_ing_hosts" \
                '. + [{source:"component", name:$name, category:$cat, namespace:$ns,
                       cluster_workloads:$wl, status:"healthy",
                       replicas_ready:$ready, replicas_desired:$desired,
                       total_restarts:$restarts, ingress_hosts:$ingress_hosts}]' \
                "$TEMP_DIR/xr_deployed.json" > "$TEMP_DIR/xr_deployed.tmp" && mv "$TEMP_DIR/xr_deployed.tmp" "$TEMP_DIR/xr_deployed.json"
        else
            jq --arg name "$comp_name" --arg cat "$comp_cat" --arg ns "$comp_ns" \
                '. + [{name:$name, category:$cat, namespace:$ns}]' \
                "$TEMP_DIR/xr_repo_only_comps.json" > "$TEMP_DIR/xr_roc.tmp" && mv "$TEMP_DIR/xr_roc.tmp" "$TEMP_DIR/xr_repo_only_comps.json"
        fi
    done

    # --- Cluster-only (untracked namespaces) ---
    echo '[]' > "$TEMP_DIR/xr_cluster_only.json"
    if [ "$CLUSTER_ONLINE" = "true" ]; then
        local tracked_ns=$(sort -u "$TEMP_DIR/xr_matched_ns.txt" 2>/dev/null || true)
        local all_ns=$(cut -d'|' -f1 "$wl_names" | sort -u)
        for ns in $all_ns; do
            [[ "$ns" == "kube-system" || "$ns" == "kube-node-lease" || "$ns" == "kube-public" ]] && continue
            echo "$tracked_ns" | grep -qx "$ns" 2>/dev/null && continue
            # Untracked namespace — add its workloads
            grep "^${ns}|" "$wl_names" | while IFS='|' read -r wns wname wkind wimg; do
                jq -n --arg kind "$wkind" --arg name "$wname" --arg ns "$wns" --arg img "$wimg" \
                    '{kind:$kind, name:$name, namespace:$ns, images:[$img]}'
            done | jq -s '.' > "$TEMP_DIR/xr_co_ns.json"
            jq --slurpfile items "$TEMP_DIR/xr_co_ns.json" '. + $items[0]' \
                "$TEMP_DIR/xr_cluster_only.json" > "$TEMP_DIR/xr_co.tmp" && mv "$TEMP_DIR/xr_co.tmp" "$TEMP_DIR/xr_cluster_only.json"
        done
    fi

    # --- Gaps ---
    jq '[.[] | select(.has_readme == false) | .name]' "$TEMP_DIR/apps.json" > "$TEMP_DIR/xr_gap_docs_a.json"
    jq '[.[] | select(.has_readme == false and .deprecated == false) | .name]' "$TEMP_DIR/components.json" > "$TEMP_DIR/xr_gap_docs_c.json"
    jq -s '.[0] + .[1]' "$TEMP_DIR/xr_gap_docs_a.json" "$TEMP_DIR/xr_gap_docs_c.json" > "$TEMP_DIR/xr_gap_docs.json"

    jq '[.[] | select(.deploy_script == "") | .name]' "$TEMP_DIR/apps.json" > "$TEMP_DIR/xr_gap_deploy.json"
    jq '[.[] | select(.dockerfile == false and .language != "unknown") | .name]' "$TEMP_DIR/apps.json" > "$TEMP_DIR/xr_gap_docker.json"
    jq '[.[] | select(.has_commands_sh == false and .deprecated == false) | .name]' "$TEMP_DIR/components.json" > "$TEMP_DIR/xr_gap_cmds.json"
    jq '[.[] | select(.deprecated == true) | .name]' "$TEMP_DIR/components.json" > "$TEMP_DIR/xr_gap_deprecated.json"

    # Assemble cross_reference.json
    jq -n \
        --slurpfile deployed "$TEMP_DIR/xr_deployed.json" \
        --slurpfile repo_only_apps "$TEMP_DIR/xr_repo_only_apps.json" \
        --slurpfile repo_only_comps "$TEMP_DIR/xr_repo_only_comps.json" \
        --slurpfile cluster_only "$TEMP_DIR/xr_cluster_only.json" \
        --slurpfile no_docs "$TEMP_DIR/xr_gap_docs.json" \
        --slurpfile no_deploy "$TEMP_DIR/xr_gap_deploy.json" \
        --slurpfile no_docker "$TEMP_DIR/xr_gap_docker.json" \
        --slurpfile no_cmds "$TEMP_DIR/xr_gap_cmds.json" \
        --slurpfile deprecated "$TEMP_DIR/xr_gap_deprecated.json" \
        --arg cluster_online "$CLUSTER_ONLINE" \
    '{
        deployed_tracked: $deployed[0],
        repo_only: {apps: $repo_only_apps[0], components: $repo_only_comps[0]},
        cluster_only: $cluster_only[0],
        gaps: {
            no_docs: $no_docs[0],
            no_deploy_script: $no_deploy[0],
            no_dockerfile: $no_docker[0],
            no_commands_sh: $no_cmds[0],
            deprecated: $deprecated[0]
        },
        cluster_online: ($cluster_online == "true")
    }' > "$TEMP_DIR/cross_reference.json"

    # Summary
    local dt=$(jq '.deployed_tracked | length' "$TEMP_DIR/cross_reference.json")
    local ro=$(jq '(.repo_only.apps | length) + (.repo_only.components | length)' "$TEMP_DIR/cross_reference.json")
    local co=$(jq '.cluster_only | length' "$TEMP_DIR/cross_reference.json")
    echo -e "  ${GREEN}✓${NC} Deployed & tracked: ${dt} | Repo-only: ${ro} | Cluster-only: ${co}"
}

# ==============================================================================
# PHASE 4: ASSEMBLE CATALOG JSON
# ==============================================================================
assemble_json() {
    echo -e "${BLUE}📋 Assembling catalog.json...${NC}"
    jq -n \
        --arg generated_at "$NOW_ISO" \
        --arg repo_root "$REPO_ROOT" \
        --arg cluster "$MASTER_NODE" \
        --slurpfile apps "$TEMP_DIR/apps.json" \
        --slurpfile components "$TEMP_DIR/components.json" \
        --slurpfile workloads "$TEMP_DIR/cluster_workloads.json" \
        --slurpfile services "$TEMP_DIR/cluster_services.json" \
        --slurpfile ingresses "$TEMP_DIR/cluster_ingresses.json" \
        --slurpfile xref "$TEMP_DIR/cross_reference.json" \
    '{
        generated_at: $generated_at,
        repo_root: $repo_root,
        cluster: $cluster,
        cluster_online: $xref[0].cluster_online,
        apps: $apps[0],
        components: $components[0],
        cluster_state: {
            workloads: $workloads[0],
            services: $services[0],
            ingresses: $ingresses[0]
        },
        cross_reference: $xref[0]
    }' > "$CATALOG_JSON"
    echo -e "  ${GREEN}✓${NC} $CATALOG_JSON ($(du -h "$CATALOG_JSON" | cut -f1))"
}

# ==============================================================================
# PHASE 5: RENDER MARKDOWN
# ==============================================================================
render_markdown() {
    echo -e "${BLUE}📝 Rendering Markdown report...${NC}"

    local apps_total=$(jq '.apps | length' "$CATALOG_JSON")
    local comps_total=$(jq '.components | length' "$CATALOG_JSON")
    local apps_deployable=$(jq '[.apps[] | select(.deploy_readiness == "deployable" or .deploy_readiness == "deployed")] | length' "$CATALOG_JSON")
    local cluster_wl=$(jq '.cluster_state.workloads | length' "$CATALOG_JSON")
    local deployed=$(jq '.cross_reference.deployed_tracked | length' "$CATALOG_JSON")
    local repo_only=$(jq '(.cross_reference.repo_only.apps | length) + (.cross_reference.repo_only.components | length)' "$CATALOG_JSON")
    local cluster_only=$(jq '.cross_reference.cluster_only | length' "$CATALOG_JSON")
    local gaps_docs=$(jq '.cross_reference.gaps.no_docs | length' "$CATALOG_JSON")
    local gaps_deploy=$(jq '.cross_reference.gaps.no_deploy_script | length' "$CATALOG_JSON")
    local gaps_docker=$(jq '.cross_reference.gaps.no_dockerfile | length' "$CATALOG_JSON")
    local online=$(jq -r '.cluster_online' "$CATALOG_JSON")

    {
        echo "# 📚 Infrastructure Catalog — $(date +%Y-%m-%d)"
        echo ""
        echo "> Generated: $NOW_ISO | Cluster: \`$MASTER_NODE\` | Online: $([ "$online" = "true" ] && echo "🟢 Yes" || echo "🔴 Offline")"
        echo ""

        # --- Executive Summary ---
        echo "## Executive Summary"
        echo ""
        echo "| Metric | Count |"
        echo "|--------|-------|"
        echo "| **Applications** (apps/) | $apps_total total ($apps_deployable deployable/deployed) |"
        echo "| **Components** (components/) | $comps_total total |"
        echo "| **Cluster Workloads** | $cluster_wl |"
        echo "| ✅ Deployed & Tracked | $deployed |"
        echo "| 📦 Repo-Only (pending) | $repo_only |"
        echo "| 🔴 Cluster-Only (untracked) | $cluster_only |"
        echo "| 📝 Missing Docs | $gaps_docs |"
        echo "| 🔧 Missing Deploy Script | $gaps_deploy |"
        echo "| 🐳 Missing Dockerfile | $gaps_docker |"
        echo ""

        # --- Apps ---
        echo "## 🚀 Applications (\`apps/\`)"
        echo ""
        echo "| App | Language | Framework | Version | Port | Dockerfile | K8s | Deploy | Docs | Readiness | Missing |"
        echo "|-----|----------|-----------|---------|------|-----------|-----|--------|------|-----------|---------||"
        jq -r '.apps[] |
            "| **\(.name)** | \(.language) | \(.framework // "-") | \(.version // "-") | \(.exposed_port // "-") | " +
            (if .dockerfile then "✅" else "❌" end) + " | " +
            (if .k8s_manifests then "✅" else "❌" end) + " | " +
            (if .deploy_script != "" then "✅" else "❌" end) + " | " +
            (if .has_readme then "✅" else "❌" end) + " | " +
            (.deploy_readiness // "wip") + " | " +
            (.readiness_missing // "-") + " |"
        ' "$CATALOG_JSON"
        echo ""

        # --- Components ---
        echo "## ⚙️ Infrastructure Components (\`components/\`)"
        echo ""
        echo "| Component | Category | Namespace | Version | Method | commands.sh | Docs | Deprecated |"
        echo "|-----------|----------|-----------|---------|--------|------------|------|------------|"
        jq -r '.components[] |
            "| **\(.name)** | \(.category) | \(.namespace // "-") | \(.version // "-") | \(.deploy_method) | " +
            (if .has_commands_sh then "✅" else "❌" end) + " | " +
            (if .has_readme then "✅" else "❌" end) + " | " +
            (if .deprecated then "🗑️" else "-" end) + " |"
        ' "$CATALOG_JSON"
        echo ""

        # --- Cluster State ---
        if [ "$online" = "true" ]; then
            echo "## ☸️ Cluster State (Live)"
            echo ""
            echo "| Workload | Kind | Namespace | Image | Replicas | Status |"
            echo "|----------|------|-----------|-------|----------|--------|"
            jq -r '.cluster_state.workloads[] |
                "| \(.name) | \(.kind) | \(.namespace) | \(.images[0] // "-") | " +
                "\(.ready_replicas // "?")/\(.replicas // "?") | " +
                (if (.ready_replicas // 0) >= (.replicas // 1) then "✅" else "⚠️" end) + " |"
            ' "$CATALOG_JSON"
            echo ""

            echo "### Ingresses"
            echo ""
            echo "| Name | Namespace | Hosts | TLS |"
            echo "|------|-----------|-------|-----|"
            jq -r '.cluster_state.ingresses[] |
                "| \(.name) | \(.namespace) | \(.hosts | join(", ")) | " +
                (if .tls then "🔒" else "❌" end) + " |"
            ' "$CATALOG_JSON"
            echo ""
        else
            echo "## ☸️ Cluster State"
            echo ""
            echo "> 🔴 Cluster offline — no live data available. Connect tunnel and re-run."
            echo ""
        fi

        # --- Cross-Reference ---
        echo "## 🔄 Cross-Reference"
        echo ""

        echo "### ✅ Deployed & Tracked ($deployed)"
        echo ""
        if [ "$deployed" -gt 0 ]; then
            echo "| Source | Name | Namespace | Replicas | Restarts | Drift | Workloads |"
            echo "|--------|------|-----------|----------|----------|-------|----------|"
            jq -r '.cross_reference.deployed_tracked[] |
                "| \(.source) | **\(.name)** | \(.cluster_namespace // .namespace // "-") | " +
                "\(.replicas_ready // 0)/\(.replicas_desired // 0) | " +
                "\(.total_restarts // 0) | " +
                (if .version_drift == "in-sync" then "🟢" elif .version_drift == "drift" then "🟡" else "-" end) + " | " +
                ((.cluster_workloads // []) | join(", ")) + " |"
            ' "$CATALOG_JSON"
        fi
        echo ""

        echo "### 📦 Repo-Only — Not Deployed ($repo_only)"
        echo ""
        local ra=$(jq '.cross_reference.repo_only.apps | length' "$CATALOG_JSON")
        if [ "$ra" -gt 0 ]; then
            echo "**Apps:**"
            echo ""
            jq -r '.cross_reference.repo_only.apps[] |
                "- \(.name) (\(.language), readiness: \(.readiness))" +
                (if (.readiness_missing // "") != "" then " — missing: \(.readiness_missing)" else "" end)
            ' "$CATALOG_JSON"
            echo ""
        fi
        local rc=$(jq '.cross_reference.repo_only.components | length' "$CATALOG_JSON")
        if [ "$rc" -gt 0 ]; then
            echo "**Components:**"
            echo ""
            jq -r '.cross_reference.repo_only.components[] |
                "- \(.name) (\(.category), ns: \(.namespace // "?"))"
            ' "$CATALOG_JSON"
            echo ""
        fi

        if [ "$cluster_only" -gt 0 ]; then
            echo "### 🔴 Cluster-Only — Untracked ($cluster_only)"
            echo ""
            echo "| Kind | Name | Namespace | Image |"
            echo "|------|------|-----------|-------|"
            jq -r '.cross_reference.cluster_only[] |
                "| \(.kind) | \(.name) | \(.namespace) | \((.images // ["?"])[0]) |"
            ' "$CATALOG_JSON"
            echo ""
        fi

        # --- Gap Analysis ---
        echo "## 📊 Gap Analysis"
        echo ""

        echo "### 📝 Missing Documentation ($gaps_docs)"
        jq -r '.cross_reference.gaps.no_docs[] | "- " + .' "$CATALOG_JSON" 2>/dev/null || true
        echo ""

        echo "### 🔧 Missing Deploy Script ($gaps_deploy apps)"
        jq -r '.cross_reference.gaps.no_deploy_script[] | "- " + .' "$CATALOG_JSON" 2>/dev/null || true
        echo ""

        echo "### 🐳 Missing Dockerfile ($gaps_docker apps)"
        jq -r '.cross_reference.gaps.no_dockerfile[] | "- " + .' "$CATALOG_JSON" 2>/dev/null || true
        echo ""

        local gaps_cmds=$(jq '.cross_reference.gaps.no_commands_sh | length' "$CATALOG_JSON")
        echo "### ⚙️ Missing commands.sh ($gaps_cmds components)"
        jq -r '.cross_reference.gaps.no_commands_sh[] | "- " + .' "$CATALOG_JSON" 2>/dev/null || true
        echo ""

        local deprecated_count=$(jq '.cross_reference.gaps.deprecated | length' "$CATALOG_JSON")
        if [ "$deprecated_count" -gt 0 ]; then
            echo "### 🗑️ Deprecated ($deprecated_count)"
            jq -r '.cross_reference.gaps.deprecated[] | "- " + .' "$CATALOG_JSON" 2>/dev/null || true
            echo ""
        fi

    } > "$CATALOG_MD"
    echo -e "  ${GREEN}✓${NC} $CATALOG_MD"
}

# ==============================================================================
# PHASE 6: RENDER HTML (SPA)
# ==============================================================================
render_html() {
    echo -e "${BLUE}🌐 Rendering HTML SPA report...${NC}"

    cat > "$CATALOG_HTML" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Infrastructure Catalog</title>
<style>
:root{--bg:#0d1117;--card:#161b22;--card2:#1c2128;--border:#30363d;--text:#c9d1d9;--dim:#8b949e;--green:#3fb950;--yellow:#d29922;--red:#f85149;--blue:#58a6ff;--purple:#bc8cff;--orange:#f0883e}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:var(--bg);color:var(--text);line-height:1.5}
a{color:var(--blue);text-decoration:none}
/* Layout */
.header{padding:20px 24px 0;border-bottom:1px solid var(--border);position:sticky;top:0;background:var(--bg);z-index:100}
.title-row{display:flex;align-items:center;gap:12px;margin-bottom:6px}
h1{color:var(--blue);font-size:1.4em}
.meta{color:var(--dim);font-size:.85em;margin-bottom:12px}
.tabs{display:flex;gap:0;margin-bottom:-1px}
.tab{padding:10px 20px;cursor:pointer;border:1px solid transparent;border-bottom:none;border-radius:6px 6px 0 0;font-size:.9em;color:var(--dim);user-select:none;transition:background .15s}
.tab:hover{background:var(--card2);color:var(--text)}
.tab.active{background:var(--card);color:var(--blue);border-color:var(--border)}
.content{padding:20px 24px}
/* Summary cards */
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin-bottom:24px}
.card{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:14px;text-align:center;cursor:pointer;transition:border-color .15s}
.card:hover{border-color:var(--blue)}
.card .n{font-size:1.8em;font-weight:700}.card .l{font-size:.8em;color:var(--dim);margin-top:2px}
.cn-green .n{color:var(--green)}.cn-yellow .n{color:var(--yellow)}.cn-red .n{color:var(--red)}.cn-blue .n{color:var(--blue)}.cn-purple .n{color:var(--purple)}
/* Toolbar */
.toolbar{display:flex;flex-wrap:wrap;gap:10px;align-items:center;margin-bottom:12px}
.search-box{background:var(--card);border:1px solid var(--border);color:var(--text);padding:7px 12px;border-radius:6px;width:260px;font-size:.88em}
.search-box:focus{outline:none;border-color:var(--blue)}
.filter-sel{background:var(--card);border:1px solid var(--border);color:var(--text);padding:7px 10px;border-radius:6px;font-size:.88em;cursor:pointer}
.filter-sel:focus{outline:none;border-color:var(--blue)}
/* Tables */
table{width:100%;border-collapse:collapse;font-size:.88em}
thead th{background:var(--card);color:var(--blue);text-align:left;padding:9px 12px;border-bottom:2px solid var(--border);white-space:nowrap;cursor:pointer;user-select:none}
thead th:hover{color:var(--purple)}thead th.sorted-asc::after{content:" ↑";opacity:.7}thead th.sorted-desc::after{content:" ↓";opacity:.7}
tbody td{padding:8px 12px;border-bottom:1px solid var(--border);vertical-align:top}
tbody tr.data-row{cursor:pointer}tbody tr.data-row:hover td{background:rgba(88,166,255,.05)}
tbody tr.detail-row{display:none}tbody tr.detail-row.open{display:table-row}
tbody tr.detail-row td{background:var(--card2);padding:14px 20px;font-size:.85em}
/* Badges */
.badge{display:inline-block;padding:2px 8px;border-radius:10px;font-size:.78em;font-weight:600;vertical-align:middle}
.b-green{background:rgba(63,185,80,.15);color:var(--green)}
.b-blue{background:rgba(88,166,255,.15);color:var(--blue)}
.b-yellow{background:rgba(210,153,34,.15);color:var(--yellow)}
.b-red{background:rgba(248,81,73,.15);color:var(--red)}
.b-dim{background:rgba(139,148,158,.1);color:var(--dim)}
.b-orange{background:rgba(240,136,62,.15);color:var(--orange)}
/* Replica badge */
.rep{font-weight:600;font-size:.85em}
.rep-ok{color:var(--green)}.rep-bad{color:var(--red)}.rep-zero{color:var(--dim)}
/* Detail grid */
.detail-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:10px 24px}
.detail-grid dt{color:var(--dim);font-size:.8em;text-transform:uppercase;letter-spacing:.05em;margin-bottom:2px}
.detail-grid dd{color:var(--text);margin-bottom:8px;word-break:break-all}
/* Tab panes */
.pane{display:none}.pane.active{display:block}
/* Ingresses */
.hosts{display:flex;flex-wrap:wrap;gap:6px}
.host-chip{background:rgba(63,185,80,.1);border:1px solid rgba(63,185,80,.2);color:var(--green);padding:2px 8px;border-radius:4px;font-size:.82em}
/* Gaps */
.gap-list{list-style:none;display:grid;grid-template-columns:repeat(auto-fill,minmax(200px,1fr));gap:6px;margin-bottom:16px}
.gap-list li{background:var(--card);border:1px solid var(--border);border-radius:6px;padding:6px 12px;font-size:.88em;color:var(--yellow)}
/* Missing badge */
.missing-tag{background:rgba(248,81,73,.1);color:var(--red);border-radius:4px;padding:1px 6px;font-size:.78em;margin-left:4px}
/* Drift */
.drift-sync{color:var(--green);font-size:.82em}.drift-drift{color:var(--yellow);font-size:.82em}.drift-unknown{color:var(--dim);font-size:.82em}
/* Deploy action */
.cmd-line{display:block;background:#0d1117;border:1px solid var(--border);border-radius:4px;padding:6px 10px;font-family:monospace;font-size:.85em;color:var(--green);margin-bottom:6px;word-break:break-all}
.btn-copy{background:rgba(88,166,255,.1);border:1px solid var(--blue);color:var(--blue);padding:4px 10px;border-radius:5px;font-size:.8em;cursor:pointer;transition:background .15s}
.btn-copy:hover{background:rgba(88,166,255,.25)}
.btn-link{background:rgba(63,185,80,.1);border:1px solid var(--green);color:var(--green);padding:4px 10px;border-radius:5px;font-size:.8em;text-decoration:none;transition:background .15s}
.btn-link:hover{background:rgba(63,185,80,.25)}
</style>
</head>
<body>
HTMLEOF

    echo "<script>const CATALOG=" >> "$CATALOG_HTML"
    cat "$CATALOG_JSON" >> "$CATALOG_HTML"
    echo ";</script>" >> "$CATALOG_HTML"

    cat >> "$CATALOG_HTML" <<'HTMLBODY'
<div class="header">
  <div class="title-row">
    <h1>📚 Infrastructure Catalog</h1>
    <span id="online-badge"></span>
  </div>
  <div class="meta" id="meta"></div>
  <div class="tabs">
    <div class="tab active" onclick="showTab('apps')">🚀 Apps</div>
    <div class="tab" onclick="showTab('components')">⚙️ Components</div>
    <div class="tab" onclick="showTab('cluster')">☸️ Cluster</div>
    <div class="tab" onclick="showTab('xref')">🔄 Cross-Ref</div>
    <div class="tab" onclick="showTab('gaps')">📊 Gaps</div>
  </div>
</div>

<div class="content">
  <!-- Cards shown on all tabs -->
  <div class="cards" id="summary-cards"></div>

  <!-- APPS TAB -->
  <div id="pane-apps" class="pane active">
    <div class="toolbar">
      <input id="apps-search" class="search-box" placeholder="Search apps…" oninput="applyFilters('apps')">
      <select id="apps-lang" class="filter-sel" onchange="applyFilters('apps')"><option value="">All languages</option></select>
      <select id="apps-readiness" class="filter-sel" onchange="applyFilters('apps')">
        <option value="">All readiness</option>
        <option>deployed</option><option>deployable</option><option>partial</option><option>wip</option><option>infra-only</option>
      </select>
    </div>
    <table id="apps-table">
      <thead><tr>
        <th data-col="0">App</th><th data-col="1">Language</th><th data-col="2">Framework</th>
        <th data-col="3">Version</th><th data-col="4">Port</th>
        <th data-col="5">Dockerfile</th><th data-col="6">K8s</th><th data-col="7">Deploy</th>
        <th data-col="8">Docs</th><th data-col="9">Readiness</th><th data-col="10">Action</th>
      </tr></thead>
      <tbody id="apps-tbody"></tbody>
    </table>
  </div>

  <!-- COMPONENTS TAB -->
  <div id="pane-components" class="pane">
    <div class="toolbar">
      <input id="comp-search" class="search-box" placeholder="Search components…" oninput="applyFilters('comp')">
      <select id="comp-cat" class="filter-sel" onchange="applyFilters('comp')"><option value="">All categories</option></select>
    </div>
    <table id="comp-table">
      <thead><tr>
        <th data-col="0">Component</th><th data-col="1">Category</th><th data-col="2">Namespace</th>
        <th data-col="3">Version</th><th data-col="4">Method</th>
        <th data-col="5">commands.sh</th><th data-col="6">Docs</th>
      </tr></thead>
      <tbody id="comp-tbody"></tbody>
    </table>
  </div>

  <!-- CLUSTER TAB -->
  <div id="pane-cluster" class="pane">
    <div id="cluster-content"></div>
  </div>

  <!-- CROSS-REF TAB -->
  <div id="pane-xref" class="pane">
    <div id="xref-content"></div>
  </div>

  <!-- GAPS TAB -->
  <div id="pane-gaps" class="pane">
    <div id="gaps-content"></div>
  </div>
</div>

<script>
const Y='✅', N='❌';
const C=CATALOG, xr=C.cross_reference, g=xr.gaps;

// ── Helpers ──────────────────────────────────────────────────────────────────
function badge(t,cls){return`<span class="badge ${cls}">${t}</span>`;}
function readinessBadge(r){
  const m={deployed:'b-green',deployable:'b-blue',partial:'b-yellow',wip:'b-orange','infra-only':'b-dim'};
  return badge(r,m[r]||'b-dim');
}
function repBadge(rdy,des){
  if(des===0||des==null) return`<span class="rep rep-zero">—</span>`;
  const ok=rdy>=des;
  return`<span class="rep ${ok?'rep-ok':'rep-bad'}">${rdy}/${des}</span>`;
}
function driftBadge(d,img){
  if(!d||d==='unknown') return'';
  if(d==='in-sync') return`<span class="drift-sync" title="${img||''}">🟢 in-sync</span>`;
  return`<span class="drift-drift" title="${img||''}">🟡 drift</span>`;
}
function hostChips(hosts){
  if(!hosts||!hosts.length) return'—';
  return`<div class="hosts">${hosts.map(h=>`<a class="host-chip" href="https://${h}" target="_blank">${h}</a>`).join('')}</div>`;
}
function esc(s){const d=document.createElement('div');d.textContent=s||'';return d.innerHTML;}

// ── Meta / Online badge ───────────────────────────────────────────────────────
document.getElementById('meta').textContent=`Generated: ${C.generated_at} | Cluster: ${C.cluster}`;
document.getElementById('online-badge').innerHTML=C.cluster_online
  ?badge('🟢 Cluster Online','b-green')
  :badge('🔴 Cluster Offline','b-red');

// ── Summary Cards ─────────────────────────────────────────────────────────────
const cardsDef=[
  {n:C.apps.length,l:'Apps',c:'cn-blue',tab:'apps'},
  {n:C.components.length,l:'Components',c:'cn-blue',tab:'components'},
  {n:C.cluster_state.workloads.length,l:'Workloads',c:'cn-blue',tab:'cluster'},
  {n:xr.deployed_tracked.length,l:'Deployed',c:'cn-green',tab:'xref'},
  {n:xr.repo_only.apps.length+xr.repo_only.components.length,l:'Repo-Only',c:'cn-yellow',tab:'xref'},
  {n:xr.cluster_only.length,l:'Cluster-Only',c:'cn-red',tab:'xref'},
  {n:g.no_docs.length,l:'Missing Docs',c:g.no_docs.length?'cn-yellow':'cn-green',tab:'gaps'},
  {n:g.no_dockerfile.length,l:'No Dockerfile',c:g.no_dockerfile.length?'cn-yellow':'cn-green',tab:'gaps'},
];
document.getElementById('summary-cards').innerHTML=cardsDef.map(c=>
  `<div class="card ${c.c}" onclick="showTab('${c.tab}')"><div class="n">${c.n}</div><div class="l">${c.l}</div></div>`
).join('');

// ── Tab switching ─────────────────────────────────────────────────────────────
let currentTab='apps';
function showTab(name){
  document.querySelectorAll('.tab').forEach((t,i)=>{
    const tabs=['apps','components','cluster','xref','gaps'];
    t.classList.toggle('active',tabs[i]===name);
  });
  document.querySelectorAll('.pane').forEach(p=>p.classList.remove('active'));
  document.getElementById('pane-'+name).classList.add('active');
  currentTab=name;
}

// ── Apps table ────────────────────────────────────────────────────────────────
// Populate language filter
const langs=[...new Set(C.apps.map(a=>a.language).filter(Boolean))].sort();
const lf=document.getElementById('apps-lang');
langs.forEach(l=>{const o=document.createElement('option');o.textContent=l;lf.appendChild(o);});

function copyCmd(btn,cmd){
  navigator.clipboard.writeText(cmd).then(()=>{
    const orig=btn.textContent;
    btn.textContent='✅ Copied!';
    setTimeout(()=>btn.textContent=orig,2000);
  }).catch(()=>{
    btn.textContent='⚠️ Failed';
    setTimeout(()=>btn.textContent='📋 Copy',2000);
  });
}

function buildAppsRows(data){
  const tb=document.getElementById('apps-tbody');
  tb.innerHTML='';
  data.forEach((a,i)=>{
    const r=a.deploy_readiness||'wip';
    const canDeploy=!!(a.deploy_cmd);
    const missingHtml=a.readiness_missing?a.readiness_missing.split(',').map(m=>`<span class="missing-tag">${m.trim()}</span>`).join(' '):'';
    const actionHtml=canDeploy
      ?`<button class="btn-copy" onclick="event.stopPropagation();copyCmd(this,${JSON.stringify(a.deploy_cmd)})">📋 Copy</button>`
      :'<span style="color:var(--dim)">—</span>';
    const dataRow=document.createElement('tr');
    dataRow.className='data-row';
    dataRow.dataset.idx=i;
    dataRow.innerHTML=`
      <td><b>${esc(a.name)}</b>${missingHtml}</td>
      <td>${esc(a.language)}</td>
      <td>${esc(a.framework||'-')}</td>
      <td>${esc(a.version||'-')}</td>
      <td>${esc(a.exposed_port||'-')}</td>
      <td>${a.dockerfile?Y:N}</td>
      <td>${a.k8s_manifests?Y:N}</td>
      <td>${a.deploy_script?Y:N}</td>
      <td>${a.has_readme?Y:N}</td>
      <td>${readinessBadge(r)}</td>
      <td>${actionHtml}</td>`;
    const deploySection=canDeploy?`
      <div><dt>Deploy Command</dt><dd>
        <code class="cmd-line">${esc(a.deploy_cmd)}</code>
        <span style="display:inline-flex;gap:8px;margin-top:6px">
          <button class="btn-copy" onclick="copyCmd(this,${JSON.stringify(a.deploy_cmd)})">📋 Copy command</button>
          <button class="btn-link" onclick="copyCmd(this,${JSON.stringify(a.deploy_script_path)});event.stopPropagation()">📄 Copy path</button>
        </span>
      </dd></div>`:'';
    const detailRow=document.createElement('tr');
    detailRow.className='detail-row';
    detailRow.innerHTML=`<td colspan="11"><div class="detail-grid">
      <div><dt>Base Image</dt><dd>${esc(a.base_image||'-')}</dd></div>
      <div><dt>Key Deps</dt><dd>${esc(Array.isArray(a.key_deps)?a.key_deps.join(', '):(a.key_deps||'-'))}</dd></div>
      <div><dt>K8s Kinds</dt><dd>${esc(Array.isArray(a.k8s_kinds)?a.k8s_kinds.join(', '):(a.k8s_kinds||'-'))}</dd></div>
      <div><dt>Exposed Port</dt><dd>${esc(a.exposed_port||'-')}</dd></div>
      <div><dt>Has Commands</dt><dd>${a.has_commands_sh?Y:N}</dd></div>
      <div><dt>Readiness Missing</dt><dd>${esc(a.readiness_missing||'-')}</dd></div>
      ${deploySection}
    </div></td>`;
    dataRow.addEventListener('click',()=>detailRow.classList.toggle('open'));
    tb.appendChild(dataRow);
    tb.appendChild(detailRow);
  });
}
buildAppsRows(C.apps);
setupSort('apps-table','apps');

function applyFilters(scope){
  if(scope==='apps'){
    const q=(document.getElementById('apps-search').value||'').toLowerCase();
    const langF=document.getElementById('apps-lang').value;
    const readF=document.getElementById('apps-readiness').value;
    const filtered=C.apps.filter(a=>{
      if(langF&&a.language!==langF)return false;
      if(readF&&(a.deploy_readiness||'wip')!==readF)return false;
      if(q&&!JSON.stringify(a).toLowerCase().includes(q))return false;
      return true;
    });
    buildAppsRows(filtered);
  } else {
    const q=(document.getElementById('comp-search').value||'').toLowerCase();
    const catF=document.getElementById('comp-cat').value;
    const filtered=C.components.filter(c=>{
      if(c.deprecated)return false;
      if(catF&&c.category!==catF)return false;
      if(q&&!JSON.stringify(c).toLowerCase().includes(q))return false;
      return true;
    });
    buildCompRows(filtered);
  }
}

// ── Components table ──────────────────────────────────────────────────────────
const cats=[...new Set(C.components.map(c=>c.category).filter(Boolean))].sort();
const cf=document.getElementById('comp-cat');
cats.forEach(c=>{const o=document.createElement('option');o.textContent=c;cf.appendChild(o);});

function buildCompRows(data){
  const tb=document.getElementById('comp-tbody');
  tb.innerHTML='';
  data.forEach(c=>{
    const dataRow=document.createElement('tr');
    dataRow.className='data-row';
    dataRow.innerHTML=`
      <td><b>${esc(c.name)}</b>${c.deprecated?' 🗑️':''}</td>
      <td>${esc(c.category)}</td>
      <td>${esc(c.namespace||'-')}</td>
      <td>${esc(c.version||'-')}</td>
      <td>${esc(c.deploy_method)}</td>
      <td>${c.has_commands_sh?Y:N}</td>
      <td>${c.has_readme?Y:N}</td>`;
    const detailRow=document.createElement('tr');
    detailRow.className='detail-row';
    detailRow.innerHTML=`<td colspan="7"><div class="detail-grid">
      <div><dt>Images</dt><dd>${esc(Array.isArray(c.images)?c.images.join(', '):(c.images||'-'))}</dd></div>
      <div><dt>K8s Kinds</dt><dd>${esc(Array.isArray(c.k8s_kinds)?c.k8s_kinds.join(', '):(c.k8s_kinds||'-'))}</dd></div>
      <div><dt>Storage PVCs</dt><dd>${esc(c.storage_pvcs||'-')}</dd></div>
    </div></td>`;
    dataRow.addEventListener('click',()=>detailRow.classList.toggle('open'));
    tb.appendChild(dataRow);
    tb.appendChild(detailRow);
  });
}
buildCompRows(C.components.filter(c=>!c.deprecated));
setupSort('comp-table','comp');

// ── Cluster tab ───────────────────────────────────────────────────────────────
(function(){
  const el=document.getElementById('cluster-content');
  if(!C.cluster_online){
    el.innerHTML='<p style="color:var(--red);padding:16px">🔴 Cluster offline — connect tunnel and re-run.</p>';
    return;
  }
  let h='<h2 style="margin:0 0 16px">☸️ Workloads</h2>';
  h+='<table><thead><tr><th>Workload</th><th>Kind</th><th>Namespace</th><th>Replicas</th><th>Restarts</th><th>Image</th></tr></thead><tbody>';
  C.cluster_state.workloads.forEach(w=>{
    const ok=(w.ready_replicas||0)>=(w.replicas||1)&&(w.replicas||0)>0;
    h+=`<tr><td><b>${esc(w.name)}</b></td><td>${esc(w.kind)}</td><td>${esc(w.namespace)}</td>
      <td>${repBadge(w.ready_replicas??0,w.replicas??0)}</td>
      <td style="color:${(w.restarts||0)>0?'var(--yellow)':'var(--dim)'}">${w.restarts??0}</td>
      <td style="font-size:.8em">${esc((w.images||['?'])[0])}</td></tr>`;
  });
  h+='</tbody></table>';
  if(C.cluster_state.ingresses.length){
    h+='<h2 style="margin:24px 0 16px">🌐 Ingresses</h2>';
    h+='<table><thead><tr><th>Name</th><th>Namespace</th><th>Hosts</th><th>TLS</th></tr></thead><tbody>';
    C.cluster_state.ingresses.forEach(i=>{
      h+=`<tr><td><b>${esc(i.name)}</b></td><td>${esc(i.namespace)}</td><td>${hostChips(i.hosts)}</td><td>${i.tls?'🔒':N}</td></tr>`;
    });
    h+='</tbody></table>';
  }
  el.innerHTML=h;
})();

// ── Cross-ref tab ─────────────────────────────────────────────────────────────
(function(){
  const el=document.getElementById('xref-content');
  let h='';

  // Deployed & tracked
  h+=`<h2 style="margin:0 0 12px">✅ Deployed &amp; Tracked (${xr.deployed_tracked.length})</h2>`;
  if(xr.deployed_tracked.length){
    h+='<table><thead><tr><th>Source</th><th>Name</th><th>Namespace</th><th>Replicas</th><th>Restarts</th><th>Hosts</th><th>Drift</th><th>Workloads</th></tr></thead><tbody>';
    xr.deployed_tracked.forEach(d=>{
      const ns=d.cluster_namespace||d.namespace||'-';
      h+=`<tr>
        <td>${badge(d.source,d.source==='app'?'b-blue':'b-purple')}</td>
        <td><b>${esc(d.name)}</b></td>
        <td>${esc(ns)}</td>
        <td>${repBadge(d.replicas_ready??0,d.replicas_desired??0)}</td>
        <td style="color:${(d.total_restarts||0)>0?'var(--yellow)':'var(--dim)'}">${d.total_restarts??0}</td>
        <td>${hostChips(d.ingress_hosts)}</td>
        <td>${driftBadge(d.version_drift,d.cluster_image)}</td>
        <td style="font-size:.82em">${(d.cluster_workloads||[]).join(', ')}</td></tr>`;
    });
    h+='</tbody></table>';
  }

  // Repo-only
  const ro=xr.repo_only;
  const roTotal=ro.apps.length+ro.components.length;
  h+=`<h2 style="margin:24px 0 12px">📦 Repo-Only (${roTotal})</h2>`;
  if(ro.apps.length){
    h+='<h3 style="margin:0 0 8px;color:var(--dim)">Apps</h3><table><thead><tr><th>Name</th><th>Language</th><th>Readiness</th><th>Missing</th></tr></thead><tbody>';
    ro.apps.forEach(a=>{
      h+=`<tr><td>${esc(a.name)}</td><td>${esc(a.language)}</td><td>${readinessBadge(a.readiness||'wip')}</td><td style="color:var(--red);font-size:.85em">${esc(a.readiness_missing||'-')}</td></tr>`;
    });
    h+='</tbody></table>';
  }
  if(ro.components.length){
    h+='<h3 style="margin:16px 0 8px;color:var(--dim)">Components</h3><table><thead><tr><th>Name</th><th>Category</th><th>Namespace</th></tr></thead><tbody>';
    ro.components.forEach(c=>{
      h+=`<tr><td>${esc(c.name)}</td><td>${esc(c.category)}</td><td>${esc(c.namespace||'-')}</td></tr>`;
    });
    h+='</tbody></table>';
  }

  // Cluster-only
  if(xr.cluster_only.length){
    h+=`<h2 style="margin:24px 0 12px;color:var(--red)">🔴 Cluster-Only (${xr.cluster_only.length})</h2>`;
    h+='<table><thead><tr><th>Kind</th><th>Name</th><th>Namespace</th><th>Image</th></tr></thead><tbody>';
    xr.cluster_only.forEach(w=>{
      h+=`<tr><td>${esc(w.kind)}</td><td>${esc(w.name)}</td><td>${esc(w.namespace)}</td><td style="font-size:.8em">${esc((w.images||['?'])[0])}</td></tr>`;
    });
    h+='</tbody></table>';
  }
  el.innerHTML=h;
})();

// ── Gaps tab ──────────────────────────────────────────────────────────────────
(function(){
  const el=document.getElementById('gaps-content');
  const sections=[
    {title:'📝 Missing Documentation',items:g.no_docs,color:'var(--yellow)'},
    {title:'🔧 Missing Deploy Script',items:g.no_deploy_script,color:'var(--orange)'},
    {title:'🐳 Missing Dockerfile',items:g.no_dockerfile,color:'var(--orange)'},
    {title:'⚙️ Missing commands.sh',items:g.no_commands_sh,color:'var(--dim)'},
    {title:'🗑️ Deprecated',items:g.deprecated,color:'var(--dim)'},
  ];
  let h='';
  sections.forEach(s=>{
    if(!s.items.length) return;
    h+=`<h2 style="margin:${h?'24px':0} 0 10px;color:${s.color}">${s.title} (${s.items.length})</h2>`;
    h+=`<ul class="gap-list">${s.items.map(i=>`<li>${esc(i)}</li>`).join('')}</ul>`;
  });
  if(!h) h='<p style="color:var(--green);padding:16px">🟢 No gaps detected!</p>';
  el.innerHTML=h;
})();

// ── Sorting ───────────────────────────────────────────────────────────────────
function setupSort(tableId,scope){
  const ths=document.querySelectorAll(`#${tableId} thead th`);
  ths.forEach((th,colIdx)=>{
    th.addEventListener('click',()=>{
      const t=document.getElementById(tableId);
      const asc=th.classList.contains('sorted-asc');
      ths.forEach(h=>h.classList.remove('sorted-asc','sorted-desc'));
      th.classList.add(asc?'sorted-desc':'sorted-asc');
      // Collect data rows only (skip detail rows)
      const tb=t.tBodies[0];
      const pairs=[];
      for(let i=0;i<tb.rows.length;i+=2){
        pairs.push([tb.rows[i],tb.rows[i+1]]);
      }
      const dir=asc?-1:1;
      pairs.sort((a,b)=>{
        const x=a[0].cells[colIdx]?a[0].cells[colIdx].textContent:'';
        const y=b[0].cells[colIdx]?b[0].cells[colIdx].textContent:'';
        return dir*x.localeCompare(y,undefined,{numeric:true});
      });
      pairs.forEach(([dr,dtr])=>{tb.appendChild(dr);tb.appendChild(dtr);});
    });
  });
}
</script>
</body></html>
HTMLBODY

    echo -e "  ${GREEN}✓${NC} $CATALOG_HTML"
}

# ==============================================================================
# UPDATE SYMLINK
# ==============================================================================
update_symlink() {
    local link="$REPORT_ROOT/latest-catalog"
    rm -f "$link"
    ln -s "$OUTPUT_DIR" "$link"
    echo -e "  ${GREEN}✓${NC} Symlink: reports/latest-catalog → $(basename "$OUTPUT_DIR")"
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║     📚 Unified Infrastructure Catalog (T-110)   ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
    echo ""

    local start_time=$SECONDS

    scan_apps
    echo ""
    scan_components
    echo ""
    scan_cluster
    echo ""
    cross_reference
    echo ""
    assemble_json
    render_markdown
    render_html
    update_symlink

    local elapsed=$(( SECONDS - start_time ))
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN}✅ Catalog generated in ${elapsed}s${NC}"
    echo -e "  📋 JSON:     $CATALOG_JSON"
    echo -e "  📝 Markdown: $CATALOG_MD"
    echo -e "  🌐 HTML:     $CATALOG_HTML"
    echo -e "${GREEN}════════════════════════════════════════════════════${NC}"
}

main "$@"
