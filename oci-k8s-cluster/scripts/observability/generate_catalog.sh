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
        if [[ -f "$app_dir/Dockerfile" ]]; then
            has_dockerfile=true
            base_image=$(grep -m1 '^FROM' "$app_dir/Dockerfile" 2>/dev/null | awk '{print $2}' || true)
            # If multi-stage, get last FROM
            local last_from=$(grep '^FROM' "$app_dir/Dockerfile" 2>/dev/null | tail -1 | awk '{print $2}')
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

        # --- Deploy Readiness ---
        local readiness="not-deployable"
        if $has_dockerfile && $has_k8s && $has_deploy; then
            readiness="ready"
        elif $has_dockerfile || $has_k8s; then
            readiness="partial"
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
  "has_readme": $has_readme,
  "has_commands_sh": $has_commands,
  "deploy_readiness": "$readiness",
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

        local category="" namespace="" deploy_method="raw-manifest" comp_version=""
        local has_commands=false has_readme=false deprecated=false
        local k8s_kinds="" images="" storage_pvcs=""

        # --- Category Heuristic ---
        case "$name" in
            cilium|ingress-nginx|coredns)       category="networking" ;;
            longhorn|local-path-provisioner|storage|minio) category="storage" ;;
            coroot|clickhouse|observability*|elastic-stack) category="observability" ;;
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

            # Namespace (first non-system one found)
            namespace=$(echo "$all_yamls" | xargs grep -h 'namespace:' 2>/dev/null | head -5 | awk '{print $2}' | grep -v '^$' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' || true)

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
    restarts: ([.status.containerStatuses[]?.restartCount // 0] | add),
    ready: ((.status.containerStatuses // []) | map(select(.ready == true)) | length),
    total: ((.status.containerStatuses // []) | length),
    node: .spec.nodeName
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
            jq --arg name "$app_name" --arg lang "$app_lang" --arg fw "$app_framework" \
                --argjson wl "$cluster_wl_json" --arg ns "$cluster_ns" \
                '. + [{source:"app", name:$name, language:$lang, framework:$fw, cluster_workloads:$wl, cluster_namespace:$ns, status:"healthy"}]' \
                "$TEMP_DIR/xr_deployed.json" > "$TEMP_DIR/xr_deployed.tmp" && mv "$TEMP_DIR/xr_deployed.tmp" "$TEMP_DIR/xr_deployed.json"
        else
            jq --arg name "$app_name" --arg lang "$app_lang" --arg readiness "$app_readiness" \
                '. + [{name:$name, language:$lang, readiness:$readiness}]' \
                "$TEMP_DIR/xr_repo_only_apps.json" > "$TEMP_DIR/xr_roa.tmp" && mv "$TEMP_DIR/xr_roa.tmp" "$TEMP_DIR/xr_repo_only_apps.json"
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
            jq --arg name "$comp_name" --arg cat "$comp_cat" --arg ns "$effective_ns" \
                --argjson wl "$cluster_wl_json" \
                '. + [{source:"component", name:$name, category:$cat, namespace:$ns, cluster_workloads:$wl, status:"healthy"}]' \
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
    local apps_ready=$(jq '[.apps[] | select(.deploy_readiness == "ready")] | length' "$CATALOG_JSON")
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
        echo "| **Applications** (apps/) | $apps_total total ($apps_ready deploy-ready) |"
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
        echo "| App | Language | Framework | Version | Dockerfile | K8s | Deploy | Docs | Readiness |"
        echo "|-----|----------|-----------|---------|-----------|-----|--------|------|-----------|"
        jq -r '.apps[] |
            "| **\(.name)** | \(.language) | \(.framework // "-") | \(.version // "-") | " +
            (if .dockerfile then "✅" else "❌" end) + " | " +
            (if .k8s_manifests then "✅" else "❌" end) + " | " +
            (if .deploy_script != "" then "✅" else "❌" end) + " | " +
            (if .has_readme then "✅" else "❌" end) + " | " +
            (if .deploy_readiness == "ready" then "🟢 Ready"
             elif .deploy_readiness == "partial" then "🟡 Partial"
             else "🔴 None" end) + " |"
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
            echo "| Source | Name | Namespace | Cluster Workloads | Status |"
            echo "|--------|------|-----------|-------------------|--------|"
            jq -r '.cross_reference.deployed_tracked[] |
                "| \(.source) | **\(.name)** | \(.cluster_namespace // .namespace // "-") | \(.cluster_workloads | join(", ")) | " +
                (if .status == "healthy" then "🟢" else "⚠️" end) + " |"
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
                "- \(.name) (\(.language), readiness: \(.readiness))"
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
# PHASE 6: RENDER HTML
# ==============================================================================
render_html() {
    echo -e "${BLUE}🌐 Rendering HTML report...${NC}"
    cat > "$CATALOG_HTML" <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Infrastructure Catalog</title>
<style>
:root{--bg:#0d1117;--card:#161b22;--border:#30363d;--text:#c9d1d9;--text-dim:#8b949e;--green:#3fb950;--yellow:#d29922;--red:#f85149;--blue:#58a6ff;--purple:#bc8cff}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif;background:var(--bg);color:var(--text);padding:20px;line-height:1.5}
h1{color:var(--blue);margin-bottom:5px}h2{color:var(--purple);margin:30px 0 15px;border-bottom:1px solid var(--border);padding-bottom:8px}h3{color:var(--text);margin:20px 0 10px}
.meta{color:var(--text-dim);margin-bottom:25px;font-size:.9em}
.summary{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:15px;margin:15px 0 30px}
.card{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:16px;text-align:center}
.card .num{font-size:2em;font-weight:700}.card .label{font-size:.85em;color:var(--text-dim)}
.card.green .num{color:var(--green)}.card.yellow .num{color:var(--yellow)}.card.red .num{color:var(--red)}.card.blue .num{color:var(--blue)}
table{width:100%;border-collapse:collapse;margin:10px 0 20px;font-size:.9em}
th{background:var(--card);color:var(--blue);text-align:left;padding:10px 12px;border-bottom:2px solid var(--border);cursor:pointer;user-select:none;white-space:nowrap}
th:hover{color:var(--purple)}th::after{content:" ⇅";color:var(--text-dim);font-size:.7em}
td{padding:8px 12px;border-bottom:1px solid var(--border)}
tr:hover{background:rgba(88,166,255,.05)}
.ready{color:var(--green)}.partial{color:var(--yellow)}.none{color:var(--red)}.healthy{color:var(--green)}.degraded{color:var(--yellow)}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:.8em;font-weight:600}
.badge-green{background:rgba(63,185,80,.15);color:var(--green)}.badge-yellow{background:rgba(210,153,34,.15);color:var(--yellow)}.badge-red{background:rgba(248,81,73,.15);color:var(--red)}
input.search{background:var(--card);border:1px solid var(--border);color:var(--text);padding:8px 14px;border-radius:6px;width:300px;margin:10px 0;font-size:.9em}
input.search:focus{outline:none;border-color:var(--blue)}
ul{margin:5px 0 15px 20px; list-style:none} ul li::before{content:"• ";color:var(--yellow)}
.gap-item{color:var(--yellow)}
</style>
</head>
<body>
HTML_HEAD

    # Inject data and render with inline JS
    echo "<script>const CATALOG=$(cat "$CATALOG_JSON");</script>" >> "$CATALOG_HTML"

    cat >> "$CATALOG_HTML" <<'HTML_BODY'
<h1>📚 Infrastructure Catalog</h1>
<p class="meta" id="meta"></p>

<h2>Executive Summary</h2>
<div class="summary" id="summary"></div>

<h2>🚀 Applications (<code>apps/</code>)</h2>
<input class="search" id="app-search" placeholder="Filter apps..." oninput="filterTable('apps-table',this.value)">
<table id="apps-table"><thead><tr>
<th onclick="sortTable('apps-table',0)">App</th>
<th onclick="sortTable('apps-table',1)">Language</th>
<th onclick="sortTable('apps-table',2)">Framework</th>
<th onclick="sortTable('apps-table',3)">Version</th>
<th onclick="sortTable('apps-table',4)">Dockerfile</th>
<th onclick="sortTable('apps-table',5)">K8s</th>
<th onclick="sortTable('apps-table',6)">Deploy</th>
<th onclick="sortTable('apps-table',7)">Docs</th>
<th onclick="sortTable('apps-table',8)">Readiness</th>
</tr></thead><tbody></tbody></table>

<h2>⚙️ Infrastructure Components (<code>components/</code>)</h2>
<input class="search" id="comp-search" placeholder="Filter components..." oninput="filterTable('comp-table',this.value)">
<table id="comp-table"><thead><tr>
<th onclick="sortTable('comp-table',0)">Component</th>
<th onclick="sortTable('comp-table',1)">Category</th>
<th onclick="sortTable('comp-table',2)">Namespace</th>
<th onclick="sortTable('comp-table',3)">Version</th>
<th onclick="sortTable('comp-table',4)">Method</th>
<th onclick="sortTable('comp-table',5)">commands.sh</th>
<th onclick="sortTable('comp-table',6)">Docs</th>
</tr></thead><tbody></tbody></table>

<div id="cluster-section"></div>
<div id="xref-section"></div>
<div id="gaps-section"></div>

<script>
const Y='✅', N='❌';
document.getElementById('meta').textContent=`Generated: ${CATALOG.generated_at} | Cluster: ${CATALOG.cluster} | Online: ${CATALOG.cluster_online?'🟢 Yes':'🔴 Offline'}`;

// Summary cards
const xr=CATALOG.cross_reference, g=xr.gaps;
const cards=[
  {n:CATALOG.apps.length,l:'Applications',c:'blue'},
  {n:CATALOG.components.length,l:'Components',c:'blue'},
  {n:CATALOG.cluster_state.workloads.length,l:'Cluster Workloads',c:'blue'},
  {n:xr.deployed_tracked.length,l:'Deployed & Tracked',c:'green'},
  {n:xr.repo_only.apps.length+xr.repo_only.components.length,l:'Repo-Only',c:'yellow'},
  {n:xr.cluster_only.length,l:'Cluster-Only',c:'red'},
  {n:g.no_docs.length,l:'Missing Docs',c:g.no_docs.length?'yellow':'green'},
  {n:g.no_dockerfile.length,l:'Missing Dockerfile',c:g.no_dockerfile.length?'yellow':'green'}
];
document.getElementById('summary').innerHTML=cards.map(c=>`<div class="card ${c.c}"><div class="num">${c.n}</div><div class="label">${c.l}</div></div>`).join('');

// Apps table
const at=document.querySelector('#apps-table tbody');
CATALOG.apps.forEach(a=>{
  const r=a.deploy_readiness;
  at.innerHTML+=`<tr><td><b>${a.name}</b></td><td>${a.language}</td><td>${a.framework||'-'}</td><td>${a.version||'-'}</td>
  <td>${a.dockerfile?Y:N}</td><td>${a.k8s_manifests?Y:N}</td><td>${a.deploy_script?Y:N}</td><td>${a.has_readme?Y:N}</td>
  <td><span class="badge badge-${r==='ready'?'green':r==='partial'?'yellow':'red'}">${r}</span></td></tr>`;
});

// Components table
const ct=document.querySelector('#comp-table tbody');
CATALOG.components.forEach(c=>{
  ct.innerHTML+=`<tr><td><b>${c.name}</b>${c.deprecated?' 🗑️':''}</td><td>${c.category}</td><td>${c.namespace||'-'}</td>
  <td>${c.version||'-'}</td><td>${c.deploy_method}</td><td>${c.has_commands_sh?Y:N}</td><td>${c.has_readme?Y:N}</td></tr>`;
});

// Cluster section
if(CATALOG.cluster_online){
  let h='<h2>☸️ Cluster State (Live)</h2><table><thead><tr><th>Workload</th><th>Kind</th><th>Namespace</th><th>Image</th><th>Replicas</th><th>Status</th></tr></thead><tbody>';
  CATALOG.cluster_state.workloads.forEach(w=>{
    const ok=(w.ready_replicas||0)>=(w.replicas||1);
    h+=`<tr><td>${w.name}</td><td>${w.kind}</td><td>${w.namespace}</td><td style="font-size:.8em">${(w.images||['?'])[0]}</td>
    <td>${w.ready_replicas??'?'}/${w.replicas??'?'}</td><td class="${ok?'healthy':'degraded'}">${ok?'✅':'⚠️'}</td></tr>`;
  });
  h+='</tbody></table>';
  if(CATALOG.cluster_state.ingresses.length){
    h+='<h3>Ingresses</h3><table><thead><tr><th>Name</th><th>Namespace</th><th>Hosts</th><th>TLS</th></tr></thead><tbody>';
    CATALOG.cluster_state.ingresses.forEach(i=>{h+=`<tr><td>${i.name}</td><td>${i.namespace}</td><td>${i.hosts.join(', ')}</td><td>${i.tls?'🔒':N}</td></tr>`;});
    h+='</tbody></table>';
  }
  document.getElementById('cluster-section').innerHTML=h;
}else{
  document.getElementById('cluster-section').innerHTML='<h2>☸️ Cluster State</h2><p style="color:var(--red)">🔴 Cluster offline — connect tunnel and re-run.</p>';
}

// Cross-reference
let xh='<h2>🔄 Cross-Reference</h2>';
xh+=`<h3>✅ Deployed & Tracked (${xr.deployed_tracked.length})</h3>`;
if(xr.deployed_tracked.length){
  xh+='<table><thead><tr><th>Source</th><th>Name</th><th>Namespace</th><th>Cluster Workloads</th><th>Status</th></tr></thead><tbody>';
  xr.deployed_tracked.forEach(d=>{xh+=`<tr><td>${d.source}</td><td><b>${d.name}</b></td><td>${d.cluster_namespace||d.namespace||'-'}</td><td style="font-size:.85em">${d.cluster_workloads.join(', ')}</td><td class="${d.status}">${d.status==='healthy'?'🟢':'⚠️'}</td></tr>`;});
  xh+='</tbody></table>';
}
const ro=xr.repo_only;
xh+=`<h3>📦 Repo-Only (${ro.apps.length+ro.components.length})</h3>`;
if(ro.apps.length){xh+='<b>Apps:</b><ul>'+ro.apps.map(a=>`<li>${a.name} (${a.language}, ${a.readiness})</li>`).join('')+'</ul>';}
if(ro.components.length){xh+='<b>Components:</b><ul>'+ro.components.map(c=>`<li>${c.name} (${c.category})</li>`).join('')+'</ul>';}
if(xr.cluster_only.length){
  xh+=`<h3 style="color:var(--red)">🔴 Cluster-Only (${xr.cluster_only.length})</h3>`;
  xh+='<table><thead><tr><th>Kind</th><th>Name</th><th>Namespace</th><th>Image</th></tr></thead><tbody>';
  xr.cluster_only.forEach(w=>{xh+=`<tr><td>${w.kind}</td><td>${w.name}</td><td>${w.namespace}</td><td style="font-size:.85em">${(w.images||['?'])[0]}</td></tr>`;});
  xh+='</tbody></table>';
}
document.getElementById('xref-section').innerHTML=xh;

// Gaps
let gh='<h2>📊 Gap Analysis</h2>';
const gapSections=[
  {title:'📝 Missing Documentation',items:g.no_docs},
  {title:'🔧 Missing Deploy Script',items:g.no_deploy_script},
  {title:'🐳 Missing Dockerfile',items:g.no_dockerfile},
  {title:'⚙️ Missing commands.sh',items:g.no_commands_sh},
  {title:'🗑️ Deprecated',items:g.deprecated}
];
gapSections.forEach(s=>{
  if(s.items.length){
    gh+=`<h3>${s.title} (${s.items.length})</h3><ul>${s.items.map(i=>`<li class="gap-item">${i}</li>`).join('')}</ul>`;
  }
});
document.getElementById('gaps-section').innerHTML=gh;

// Sorting
function sortTable(id,col){
  const t=document.getElementById(id),b=t.tBodies[0],rows=[...b.rows];
  const dir=t.dataset.sortCol==col&&t.dataset.sortDir==='asc'?'desc':'asc';
  t.dataset.sortCol=col;t.dataset.sortDir=dir;
  rows.sort((a,b)=>{const x=a.cells[col].textContent,y=b.cells[col].textContent;return dir==='asc'?x.localeCompare(y):y.localeCompare(x);});
  rows.forEach(r=>b.appendChild(r));
}
function filterTable(id,q){
  const rows=document.querySelectorAll(`#${id} tbody tr`);
  q=q.toLowerCase();
  rows.forEach(r=>{r.style.display=r.textContent.toLowerCase().includes(q)?'':'none';});
}
</script>
</body></html>
HTML_BODY

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
