#!/usr/bin/env bash
# scripts/observability/generate_storage_dossier.sh

SCRIPT_REAL_PATH=$(dirname "${BASH_SOURCE[0]}")
COMMON_PATH="$SCRIPT_REAL_PATH/../../common.sh"
set +e # Disable exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
GRAY='\033[0;90m'

# Setup Execution Mode
if type run_kubectl >/dev/null 2>&1; then
    MODE="remote"
    source "$COMMON_PATH" 2>/dev/null 
elif [ -f "$COMMON_PATH" ]; then
    source "$COMMON_PATH"
    if type run_kubectl >/dev/null 2>&1; then
         MODE="remote"
    else
         MODE="local"
         k_cmd="kubectl"
    fi
else
    MODE="local"
    k_cmd="kubectl"
fi
[ "$MODE" == "remote" ] && k_cmd="run_kubectl"

echo -e "\n${BLUE}📂 Generating Application Storage Dossier (Deep Dive)...${NC}"
echo -e "   (Mode: $MODE)"
echo "============================================"

exec_complex() {
    local cmd="$1"
    if [ "$MODE" == "remote" ]; then
        run_remote_raw "$MASTER_NODE" "$cmd"
    else
        eval "$cmd"
    fi
}

get_longhorn_info() {
    local ns="$1"
    local pvc_name="$2"
    local app_bytes="$3" # Optional: App usage in bytes
    
    # Get Volume Name
    local vol_name
    vol_name=$($k_cmd get pvc -n "$ns" "$pvc_name" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
    
    if [ -z "$vol_name" ]; then
        echo -e "   ${GRAY}Longhorn Info: PVC not found/unbound.${NC}"
        return
    fi
    
    # Get Longhorn Stats
    local actual_size_bytes
    actual_size_bytes=$($k_cmd get volumes.longhorn.io -n longhorn-system "$vol_name" -o jsonpath='{.status.actualSize}' 2>/dev/null || echo "0")
    
    local actual_size_human
    actual_size_human=$(numfmt --to=iec --suffix=B "$actual_size_bytes" 2>/dev/null || echo "$actual_size_bytes")
    
    # Count Snapshots
    local snap_count
    # Label is 'longhornvolume'
    local snap_cmd="kubectl get snapshots.longhorn.io -n longhorn-system --no-headers -l longhornvolume=$vol_name | wc -l"
    snap_count=$(exec_complex "$snap_cmd")
    snap_count=$(echo "$snap_count" | tr -d ' ')

    # Check Labels for Recurring Jobs
    local job_label
    # Use bracket notation for keys with special chars
    job_label=$($k_cmd get volumes.longhorn.io -n longhorn-system "$vol_name" -o jsonpath="{.metadata.labels['recurring-job\.longhorn\.io/maintenance-cleanup']}" 2>/dev/null || true)
    local job_status=""
    if [ "$job_label" == "enabled" ]; then
         job_status="${GREEN}(Auto-Cleanup Enabled)${NC}"
    else
         job_status="${RED}(No Cleanup Job)${NC}"
    fi

    echo -e "   ${GRAY}Storage Layer (Longhorn):${NC}"
    echo -e "   • Volume ID: $vol_name"
    echo -e "   • Physical: ${YELLOW}$actual_size_human${NC} $job_status"
    echo -e "   • Snapshots: ${YELLOW}$snap_count${NC}"
    
    # Efficiency Calc
    if [ -n "$app_bytes" ] && [ "$app_bytes" -gt 0 ] && [ "$actual_size_bytes" -gt 0 ]; then
         local eff=$(( app_bytes * 100 / actual_size_bytes ))
         # If efficiency is low (< 50%) and size > 1GB, warn
         local color="$GREEN"
         if [ "$eff" -lt 50 ] && [ "$actual_size_bytes" -gt 1073741824 ]; then
             color="$RED"
         elif [ "$eff" -lt 80 ]; then
             color="$YELLOW"
         fi
         echo -e "   • Efficiency: ${color}${eff}%${NC} (Logical/Physical)"
    fi
}

# --- 1. ELASTICSEARCH ---
echo -e "\n${YELLOW}1. Elasticsearch Usage${NC}"
ES_POD=$($k_cmd get pods -n elastic-system -l elasticsearch.k8s.elastic.co/cluster-name=oci-logs -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$ES_POD" ]; then
    echo -e "${RED}❌ Elasticsearch pod not found.${NC}"
else
    # App Layer
    ES_PASS_B64=$($k_cmd get secret -n elastic-system oci-logs-es-elastic-user -o jsonpath='{.data.elastic}' 2>/dev/null || true)
    if [ -n "$ES_PASS_B64" ]; then
        ES_PASS=$(echo "$ES_PASS_B64" | base64 -d 2>/dev/null)
        echo -e "${CYAN}   Pod: $ES_POD${NC}"
        CMD="kubectl exec -n elastic-system $ES_POD -- curl -s -k -u elastic:$ES_PASS 'https://localhost:9200/_cat/indices?v&s=store.size:desc&h=health,index,docs.count,store.size,pri.store.size' | head -n 6"
        exec_complex "$CMD" | sed 's/^/   /'
    else
        echo -e "   (Credentials missing)"
    fi
    # Longhorn Layer (Assuming default Claim Name pattern for StatefulSet)
    # oci-logs-es-default-0 -> claim: elasticsearch-data-oci-logs-es-default-0
    # Hard to get exact app bytes for Elastic easily from CLI summary, passing 0 to skip eff calc for now
    get_longhorn_info "elastic-system" "elasticsearch-data-oci-logs-es-default-0" "0"
fi

# --- 2. POSTGRESQL ---
echo -e "\n${YELLOW}2. PostgreSQL Usage${NC}"
PG_POD=$($k_cmd get pods -n postgres -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$PG_POD" ]; then
    echo -e "${RED}❌ Postgres pod not found.${NC}"
else
    echo -e "${CYAN}   Pod: $PG_POD${NC}"
    # Get Total DB Size in Bytes
    SQL_BYTES="SELECT SUM(pg_database_size(datname)) FROM pg_database;"
    CMD_BYTES="kubectl exec -n postgres $PG_POD -- psql -U postgres -t -c '$SQL_BYTES'"
    PG_BYTES=$(exec_complex "$CMD_BYTES" | tr -d ' ')
    
    # Display table
    SQL="SELECT datname as db, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database ORDER BY pg_database_size(datname) DESC;"
    CMD="kubectl exec -n postgres $PG_POD -- psql -U postgres -c '$SQL'"
    exec_complex "$CMD" | grep -v "row" | grep -v "\-\-\-" | head -n 5 | sed 's/^/   /'
    
    # Longhorn Info
    get_longhorn_info "postgres" "postgres-pvc" "$PG_BYTES"
fi

# --- 3. COROOT ---
echo -e "\n${YELLOW}3. Coroot (Prometheus) Metrics${NC}"
PROME_POD=$($k_cmd get pods -n coroot -l app=prometheus,component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [ -z "$PROME_POD" ]; then
    echo -e "${RED}❌ Coroot Prometheus pod not found.${NC}"
else
    echo -e "${CYAN}   Pod: $PROME_POD${NC}"
    echo -e "   App (Inside Container):"
    
    # Get Used Bytes (Avail is $4, Used is $3 in -B1 output?)
    # df -B1: 1K-blocks Used Available Use%
    # No, df -B1: 1B-blocks ...
    CMD_DF="kubectl exec -n coroot $PROME_POD -c prometheus-server -- df -B1 /data | grep '/data'"
    DF_OUT=$(exec_complex "$CMD_DF")
    # Parse Used Bytes ($3)
    COROOT_BYTES=$(echo "$DF_OUT" | awk '{print $3}')
    
    # Human readable output
    $k_cmd exec -n coroot "$PROME_POD" -c prometheus-server -- df -hP /data | grep "/data" | awk '{print "   • Used: " $3 " / " $2 " (" $5 ")"}'
    
    get_longhorn_info "coroot" "coroot-prometheus-server" "$COROOT_BYTES"
fi

echo -e "\n============================================"
echo -e "${GREEN}✅ Correlation Analysis Complete.${NC}"
