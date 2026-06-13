#!/usr/bin/env bash
# scripts/observability/generate_storage_dossier.sh
# Refactored: Dossier 3.0 - Standardized & Expanded

SCRIPT_REAL_PATH=$(dirname "${BASH_SOURCE[0]}")
# Fix: Define SCRIPT_DIR for common.sh (Project Root)
SCRIPT_DIR=$(cd "$SCRIPT_REAL_PATH/../.." && pwd)
COMMON_PATH="$SCRIPT_DIR/common.sh"
set +e # Disable exit on error

# Source Colors/Vars
if [ -f "$COMMON_PATH" ]; then
    source "$COMMON_PATH"
fi

# Ensure Colors are defined (Fallbacks/Extras)
RED=${RED:-'\033[0;31m'}
GREEN=${GREEN:-'\033[0;32m'}
YELLOW=${YELLOW:-'\033[1;33m'}
BLUE=${BLUE:-'\033[0;34m'}
CYAN=${CYAN:-'\033[0;36m'}
NC=${NC:-'\033[0m'}
BOLD=${BOLD:-'\033[1m'}
GRAY='\033[1;30m'

# Detect Mode
if type run_kubectl >/dev/null 2>&1; then
    MODE="remote"
    k_cmd="run_kubectl"
else
    MODE="local"
    k_cmd="kubectl"
fi

# ==============================================================================
# UI HELPERS
# ==============================================================================

print_banner() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ ${BOLD}🏥 STORAGE & BACKUP HEALTH DOSSIER ${NC}${BLUE}                                        ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${GRAY}   Generated at: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${GRAY}   Mode: ${MODE^^} | Cluster: OCI-K8S${NC}"
    echo ""
}

print_section_header() {
    local title="$1"
    local icon="$2"
    echo -e "${YELLOW}┌──────────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│ ${icon} ${BOLD}${title}${NC}${YELLOW}${NC}"
    echo -e "${YELLOW}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
}

exec_capture() {
    local cmd="$1"
    local desc="$2"
    if [ -n "$desc" ]; then
         printf "   • %-50s " "${desc}..." >&2
    fi
    
    local output
    # DEBUG: See what we are running
    # echo "DEBUG_CMD: $cmd" >&2
    if [ "$MODE" == "remote" ]; then
         output=$(run_remote_raw "$MASTER_NODE" "$cmd" 2>/dev/null)
    else
         output=$(eval "$cmd" 2>/dev/null)
    fi
    
    if [ -n "$desc" ]; then echo -e "${GREEN}DONE${NC}" >&2; fi
    echo "$output"
}

fmt_size() {
    local bytes="${1:-0}" # Default to 0 if unset
    if [[ -z "$bytes" || "$bytes" == "0" ]]; then echo "0 B"; return; fi
    numfmt --to=iec --suffix=B "$bytes"
}


# Standardized PV Stats Function (Enhanced)
# Standardized PV Stats Function (Handles Longhorn & Standard)
# Arg 1: Namespace
# Arg 2: PVC Name (NOT PV Name)
# Arg 3: Logical Size (Bytes) - Optional
# Arg 2: PVC Name (NOT PV Name)
# Arg 3: Logical Size (Bytes) - Optional
print_pv_stats() {
    local namespace="$1"
    local pvc_name="$2"
    local logical_size_bytes="$3"
    
    echo -e "\n   ${BOLD}Storage (PV Link):${NC}"
    
    if [ -z "$pvc_name" ] || [[ "$pvc_name" == *"No PVC Linked"* ]]; then
        echo "   No PVC Linked (Ephemeral/EmptyDir)"
        return
    fi
    
    # Check Storage Class & Capacity using custom-columns (Most robust method)
    # Output Format: SC CAPACITY (e.g. "longhorn 1Gi")
    local pvc_info=$(exec_capture "kubectl get pvc -n $namespace $pvc_name -o custom-columns=SC:.spec.storageClassName,CAP:.status.capacity.storage --no-headers 2>/dev/null" "")
    
    local sc=$(echo "$pvc_info" | awk '{print $1}')
    local capacity=$(echo "$pvc_info" | awk '{print $2}')

    # Resolve PV Name (UUID) for Longhorn Checks
    local pv_name=$(exec_capture "kubectl get pvc -n $namespace $pvc_name -o jsonpath=\"{.spec.volumeName}\" 2>/dev/null" "")
    
    # 1. Longhorn Strategy
    if [[ "$sc" == "longhorn" || "$sc" == "longhorn-2" ]]; then
        local lh_stats
        lh_stats=$(exec_capture "kubectl get volumes.longhorn.io -n longhorn-system $pv_name -o jsonpath=\"{.status.actualSize}\" 2>/dev/null || echo 0" "")
        local lh_snaps
        lh_snaps=$(exec_capture "kubectl get snapshots.longhorn.io -n longhorn-system --no-headers -l longhornvolume=$pv_name | wc -l" "")
        
        # Calculate Efficiency
        local eff="N/A"
        if [[ -n "$logical_size_bytes" && "$lh_stats" -gt 0 ]]; then
            eff=$((logical_size_bytes * 100 / lh_stats))
            eff="${eff}%"
        fi
        
        printf "   %-20s: %s\n" "Volume ID" "$pv_name"
        printf "   %-20s: %s\n" "Physical (Disk)" "$(fmt_size $lh_stats)"
        printf "   %-20s: %s\n" "Snapshots" "$(echo $lh_snaps | tr -d ' ')"
        
        if [ "$eff" != "N/A" ]; then
             printf "   %-20s: %s (Logical/Physical)\n" "Efficiency" "$eff"
        fi
    
    # 2. HostPath / Manual / Other Strategy
    else
        printf "   %-20s: %s\n" "Volume ID" "$pvc_name"
        printf "   %-20s: %s\n" "Type" "Standard (SC: $sc)"
        printf "   %-20s: %s\n" "Allocated" "$capacity"
        
        # Calculate Utilization (Usage / Capacity) for Standard PVs if usage is provided
        if [[ -n "$logical_size_bytes" && "$logical_size_bytes" != "0" ]]; then
            # We assume logical_size_bytes passed here is actually the USED bytes on disk for standard volumes
            # Need to convert Capacity (e.g. 1Gi) to bytes roughly to calc %
            # Or simpler: Just print the Usage passed in.
            local human_usage=$(fmt_size $logical_size_bytes)
            printf "   %-20s: %s (Used)\n" "Utilization" "$human_usage / $capacity"
        fi
    fi
}

# ==============================================================================
# LOGIC
# ==============================================================================

print_banner

# --- SECTION 0: CLUSTER NODES ---
print_section_header "CLUSTER NODES (Physical Storage)" "🖥️"

printf "   ${GRAY}%-12s %-8s %-8s %-8s %-8s %-8s %-8s %-8s %-8s %-8s${NC}\n" "NODE" "ROOT(%)" "SIZE" "SNAP" "ORACLE" "LGHRN" "DOCKER" "LOGS" "BCKUP" "OTHER"
echo "   ─────────────────────────────────────────────────────────────────────────────────────────────"

for node in "${NODES[@]}"; do
    CMD='
    # Calculate bytes for precision subtraction
    df_root=$(df -P / | tail -n 1)
    root_total=$(echo "$df_root" | awk "{print \$2}")
    root_used=$(echo "$df_root" | awk "{print \$3}")
    root_size=$(echo "$df_root" | awk "{print \$2}")  # Total Size (1k blocks)
    root_pct=$(echo "$df_root" | awk "{print \$5}")
    
    lh=$(sudo du -s /var/lib/longhorn 2>/dev/null | cut -f1 || echo "0")
    
    # Snapd (Package Cache/Revisions)
    snap=$(sudo du -s /var/lib/snapd 2>/dev/null | cut -f1 || echo "0")
    
    # Oracle Cloud Agent (Logs/Data if exists)
    oracle=$(sudo du -s /var/lib/oracle-cloud-agent 2>/dev/null | cut -f1 || echo "0")

    # Sum Docker (Legacy/BuildKit) + Containerd (Runtime)
    cont_d=$(sudo du -s /var/lib/docker 2>/dev/null | cut -f1 || echo "0")
    cont_c=$(sudo du -s /var/lib/containerd 2>/dev/null | cut -f1 || echo "0")
    cont=$((cont_d + cont_c))
    
    logs=$(sudo du -s /var/log 2>/dev/null | cut -f1 || echo "0")
    
    etcd="0"
    if [ -d "/var/lib/etcd" ]; then etcd=$(sudo du -s /var/lib/etcd 2>/dev/null | cut -f1); fi
    
    backup="0"
    if [ -d "/var/backup" ]; then backup=$(sudo du -s /var/backup 2>/dev/null | cut -f1); fi
    
    # Minio HostPath (Deduct from System to avoid double counting)
    minio_data="0"
    if [ -d "/data/minio" ]; then minio_data=$(sudo du -s /data/minio 2>/dev/null | cut -f1); fi
    
    # Ensure no empty values
    [ -z "$lh" ] && lh=0
    [ -z "$snap" ] && snap=0
    [ -z "$oracle" ] && oracle=0
    [ -z "$cont" ] && cont=0
    [ -z "$logs" ] && logs=0
    [ -z "$etcd" ] && etcd=0
    [ -z "$backup" ] && backup=0
    [ -z "$minio_data" ] && minio_data=0
    [ -z "$root_used" ] && root_used=0

    # System = Used - (Known Components)
    known=$((lh + snap + oracle + cont + logs + etcd + backup + minio_data))
    system=$((root_used - known))
    if [ "$system" -lt 0 ]; then system=0; fi
    
    echo "$root_pct|$root_size|$lh|$snap|$oracle|$cont|$logs|$etcd|$backup|$system"
    '
    STATS=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -T "$node" "$CMD" 2>/dev/null || echo "")
    
    if [ -z "$STATS" ]; then
         printf "   %-12s ${RED}%-10s${NC}\n" "$node" "OFFLINE"
    else
         IFS='|' read -r root root_size lh snap oracle cont logs etcd backup system <<< "$STATS"
         
         # Fallback defaults for local parsing safety
         [ -z "$lh" ] && lh=0
         [ -z "$snap" ] && snap=0
         [ -z "$oracle" ] && oracle=0
         [ -z "$cont" ] && cont=0
         [ -z "$logs" ] && logs=0
         [ -z "$etcd" ] && etcd=0
         [ -z "$backup" ] && backup=0
         [ -z "$system" ] && system=0

         # Convert back to human readable for display
         h_lh=$(numfmt --to=iec --from-unit=1024 "$lh" 2>/dev/null || echo "0B")
         h_snap=$(numfmt --to=iec --from-unit=1024 "$snap" 2>/dev/null || echo "0B")
         h_oracle=$(numfmt --to=iec --from-unit=1024 "$oracle" 2>/dev/null || echo "0B")
         h_cont=$(numfmt --to=iec --from-unit=1024 "$cont" 2>/dev/null || echo "0B")
         h_logs=$(numfmt --to=iec --from-unit=1024 "$logs" 2>/dev/null || echo "0B")
         
         h_backup="-"
         if [ "$backup" -gt 0 ]; then h_backup=$(numfmt --to=iec --from-unit=1024 "$backup" 2>/dev/null || echo "0B"); fi
         
         h_system=$(numfmt --to=iec --from-unit=1024 "$system" 2>/dev/null || echo "0B")
         h_size=$(numfmt --to=iec --from-unit=1024 "$root_size" 2>/dev/null || echo "0B")
         
         ROOT_COLOR=$GREEN
         clean_root=${root%\%}
         if [[ "$clean_root" =~ ^[0-9]+$ ]]; then
             if [ "$clean_root" -gt 85 ]; then ROOT_COLOR=$RED; elif [ "$clean_root" -gt 70 ]; then ROOT_COLOR=$YELLOW; fi
         fi
         
         printf "   %-12s ${ROOT_COLOR}%-8s${NC} %-8s %-8s %-8s %-8s %-8s %-8s %-8s %-8s\n" \
            "${node#oci-k8s-}" "$root" "$h_size" "$h_snap" "$h_oracle" "$h_lh" "$h_cont" "$h_logs" "$h_backup" "$h_system"
            
         # Alert on high system usage (>5GB approx 5000000 blocks)
         if [ "$system" -gt 5000000 ]; then
            # Drill-down with truncated paths for better readability
            drill_down=$(ssh -T $node "sudo du -xSh / 2>/dev/null | grep -vE '/var/lib/docker|/var/lib/containerd|/var/lib/longhorn|/var/lib/etcd|/var/backup|/data' | sort -rh | head -n 5 | awk '{print \$1, substr(\$2, length(\$2)-50)}'" 2>/dev/null)
            
            if [ -n "$drill_down" ]; then
                printf "   %-12s ${YELLOW}  ↳ High System Usage via:${NC}\n" ""
                echo "$drill_down" | while read -r line; do
                    printf "   %-12s ${YELLOW}    • %s${NC}\n" "" "$line"
                done
            fi
         fi
         
         # Docker Drill-down (Top 5)
         if [ "$cont" -gt 5000000 ]; then
             docker_drill=$(ssh -T $node "sudo du -xSh /var/lib/docker /var/lib/containerd 2>/dev/null | sort -rh | head -n 5 | awk '{print \$1, substr(\$2, length(\$2)-50)}'" 2>/dev/null)
             if [ -n "$docker_drill" ]; then
                printf "   %-12s ${BLUE}  ↳ Top Docker Usage:${NC}\n" ""
                echo "$docker_drill" | while read -r line; do
                    # Parse path for context (Heuristic based on end of path)
                    context=""
                    if [[ "$line" == *"/diff/"* ]]; then context=" (Image Layer)"; fi
                    if [[ "$line" == *"/merged/"* ]]; then context=" (Active Layer)"; fi
                    if [[ "$line" == *"-json.log"* ]]; then context=" (Logs)"; fi
                    if [[ "$line" == *"/volumes/"* ]]; then context=" (PV Data)"; fi
                    if [[ "$line" == *"/buildkit/"* ]]; then context=" (Build Cache)"; fi
                    
                    # Fallback for truncated paths
                    if [[ -z "$context" && "$line" == *"overlay2"* ]]; then context=" (Image)"; fi
                    if [[ -z "$context" && "$line" == *"containers"* ]]; then context=" (Container)"; fi
                    
                    printf "   %-12s ${BLUE}    • %s${GRAY}%s${NC}\n" "" "$line" "$context"
                done
             fi
         fi

         # Journal/Systemd Analysis (Top Spammers)
         if [ "$logs" -gt 100000 ]; then # >100MB
             # Get usage and then sample top units
             # Awk $5 matches 'process[pid]:' standard syslog format
             journal_top=$(ssh -T $node "journalctl --disk-usage 2>/dev/null; echo '---'; timeout 5s journalctl -n 2000 2>/dev/null | awk '{print \$5}' | grep '\[' | cut -d: -f1 | sort | uniq -c | sort -nr | head -n 5" 2>/dev/null)
             
             if [ -n "$journal_top" ]; then
                printf "   %-12s ${MAGENTA}  ↳ System Log Analysis:${NC}\n" ""
                # First line is usage
                usage_line=$(echo "$journal_top" | head -n 1)
                printf "   %-12s ${MAGENTA}    • %s${NC}\n" "" "$usage_line"
                
                # Remaining are top units
                echo "$journal_top" | sed '1,2d' | while read -r count unit; do
                   # Unit format is typically process[pid]
                   # We want to extract just the process name if possible, or keep as is
                   printf "   %-12s ${MAGENTA}    • %-20s %s entries (Recent)${NC}\n" "" "$unit" "$count"
                done
             fi
         fi
    fi
done
echo ""

# --- SECTION 1: ELASTICSEARCH (retired — Vector + MinIO planned) ---
print_section_header "LOGS PIPELINE" "🔎"
if kubectl get ns elastic-system >/dev/null 2>&1; then
    ES_POD=$(exec_capture "kubectl get pods -n elastic-system -l elasticsearch.k8s.elastic.co/cluster-name=oci-logs -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true" "Finding ES Pod")
    if [ -n "$ES_POD" ]; then
        echo -e "   ${YELLOW}⚠️  Legacy Elastic Stack still present (run uninstall_elastic_stack.sh)${NC}"
    else
        echo -e "   ${GRAY}Elastic Stack removed. Planned: Vector → Parquet on MinIO.${NC}"
    fi
else
    echo -e "   ${GRAY}Elastic Stack not deployed. Planned: Vector → Parquet on MinIO.${NC}"
fi
echo ""

# --- SECTION 2: POSTGRESQL (App DB) ---
print_section_header "POSTGRESQL (App DB)" "🐘"
# Fix: Use 'app=postgres' (Verified via kubectl get pod postgres-0 --show-labels)
PG_POD=$(exec_capture "kubectl get pods -n postgres -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true" "Finding PG Pod")
if [ -z "$PG_POD" ]; then
    echo -e "   ${RED}❌ Pod not found${NC}"
else
    SQL="SELECT datname, pg_database_size(datname) FROM pg_database ORDER BY pg_database_size(datname) DESC;"
    DB_RAW=$(exec_capture "kubectl exec -n postgres $PG_POD -- psql -U postgres -t -A -F ' ' -c '$SQL'" "Querying DB Stats")
    
    echo -e "\n   ${BOLD}Databases:${NC}"
    printf "   ${GRAY}%-20s %-15s${NC}\n" "NAME" "SIZE"
    echo "   ───────────────────────────────────"
    
    TOTAL_PG_BYTES=0
    while read -r name size; do
        if [[ -n "$name" ]]; then
             human=$(fmt_size "$size")
             printf "   %-20s %-15s\n" "$name" "$human"
             TOTAL_PG_BYTES=$((TOTAL_PG_BYTES + size))
        fi
    done <<< "$DB_RAW"

    print_pv_stats "postgres" "postgres-data-postgres-0" "$TOTAL_PG_BYTES"
fi
echo ""

# --- SECTION 3: COROOT (Prometheus) ---
print_section_header "COROOT (Prometheus)" "📊"
PROM_POD=$(exec_capture "kubectl get pods -n coroot -l app=prometheus,component=server -o jsonpath={.items[0].metadata.name} 2>/dev/null || true" "Finding Prometheus Pod")

if [ -z "$PROM_POD" ]; then
    echo -e "   ${RED}❌ Pod not found${NC}"
else
    USAGE_RAW=$(exec_capture "kubectl exec -n coroot $PROM_POD -c prometheus-server -- df -P -B1 /data | grep '/data'" "Checking Disk Usage")
    USED=$(echo "$USAGE_RAW" | awk '{print $3}')
    TOTAL=$(echo "$USAGE_RAW" | awk '{print $2}')
    PCT=$(echo "$USAGE_RAW" | awk '{print $5}')
    
    echo -e "\n   ${BOLD}Volume Usage (Container):${NC}"
    printf "   %-20s: %s / %s (%s)\n" "Usage" "$(fmt_size $USED)" "$(fmt_size $TOTAL)" "$PCT"
    
    print_pv_stats "coroot" "coroot-prometheus-server" "$USED"
fi
echo ""

# --- SECTION 4: CLICKHOUSE (Coroot DB) ---
print_section_header "CLICKHOUSE (Coroot DB)" "🏰"
# Fix: Use 'app.kubernetes.io/name=clickhouse'
CH_POD=$(exec_capture "kubectl get pods -n coroot -l app.kubernetes.io/name=clickhouse -o jsonpath={.items[0].metadata.name} 2>/dev/null || true" "Finding Clickhouse Pod")

if [ -z "$CH_POD" ]; then
    echo -e "   ${RED}❌ Pod not found${NC}"
else
    # Clickhouse Usage (du is more accurate for EmptyDir on Root)
    # df showed Node Root usage (38GB), while du shows App usage (~1GB)
    CH_USAGE=$(exec_capture "kubectl exec -n coroot $CH_POD -- du -sb /var/lib/clickhouse | cut -f1" "Checking Disk Usage")
    USED="$CH_USAGE"
    
    # Get Capacity from df just for context (Node Limit)
    TOTAL=$(exec_capture "kubectl exec -n coroot $CH_POD -- df -P -B1 /var/lib/clickhouse | grep '/var/lib/clickhouse' | head -n 1 | awk '{print \$2}'" "")
    
    # Calculate PCT manually
    if [[ -n "$USED" && -n "$TOTAL" && "$TOTAL" -gt 0 ]]; then
        PCT=$((USED * 100 / TOTAL))
        PCT="${PCT}%"
    else
        PCT="N/A"
    fi
    
    # Safety
    if [ -z "$USED" ]; then USED="0"; fi

    echo -e "\n   ${BOLD}Volume Usage (Container):${NC}"
    printf "   %-20s: %s / %s (%s)\n" "Usage" "$(fmt_size $USED)" "$(fmt_size $TOTAL)" "$PCT"
    
    # Clickhouse Table Stats
    echo -e "\n   ${BOLD}Top Tables:${NC}"
    CH_QUERY="SELECT table, formatReadableSize(sum(bytes)) as size FROM system.parts GROUP BY table ORDER BY sum(bytes) DESC LIMIT 5"
    CH_STATS=$(exec_capture "kubectl exec -n coroot $CH_POD -- clickhouse-client --query '$CH_QUERY' 2>/dev/null" "Querying DB Stats")
    
    if [ -n "$CH_STATS" ]; then
         printf "   ${GRAY}%-30s %-15s${NC}\n" "TABLE" "SIZE"
         echo "   ─────────────────────────────────────────────"
         echo "$CH_STATS" | awk '{printf "   %-30s %s %s\n", $1, $2, $3}'
    else
         echo "   (No stats available)"
    fi
    
    # PVC Name
    CH_PVC=$(exec_capture "kubectl get pod -n coroot $CH_POD -o jsonpath={.spec.volumes[?(@.name==\"data\")].persistentVolumeClaim.claimName} 2>/dev/null" "")
    
    # If using clickhouse-data name
    if [ -z "$CH_PVC" ]; then
         CH_PVC=$(exec_capture "kubectl get pod -n coroot $CH_POD -o jsonpath={.spec.volumes[?(@.name==\"clickhouse-data\")].persistentVolumeClaim.claimName} 2>/dev/null" "")
    fi
     
    VOL_NAME=""
    if [ -n "$CH_PVC" ]; then
        VOL_NAME=$(exec_capture "kubectl get pvc -n coroot $CH_PVC -o jsonpath={.spec.volumeName} 2>/dev/null || true" "")
    fi
    print_pv_stats "coroot" "$VOL_NAME" "$USED"
fi
echo ""

# --- SECTION 5: MINIO (Object Storage) ---
print_section_header "MINIO (S3 Artifacts)" "🪣"
MINIO_POD=$(exec_capture "kubectl get pods -n minio -l app=minio -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true" "Finding Minio Pod")

if [ -z "$MINIO_POD" ]; then
    echo -e "   ${RED}❌ Pod not found${NC}"
else
    # Check /export or /data usage
    # FIX: df shows Node Partition usage for HostPath. Use du for accurate App usage.
    MIN_USAGE=$(exec_capture "kubectl exec -n minio $MINIO_POD -- du -sb /data | cut -f1" "Checking Disk Usage")
    USED="$MIN_USAGE"
    
    # FIX: Minio PVC is 1Gi but PV is 20Gi (HostPath). PVC resize fails. 
    # We must fetch the PV capacity to show the true limit.
    MIN_PV_NAME=$(exec_capture "kubectl get pvc -n minio minio-pvc -o jsonpath='{.spec.volumeName}' 2>/dev/null" "")
    pvc_size=$(exec_capture "kubectl get pv $MIN_PV_NAME -o jsonpath='{.spec.capacity.storage}' 2>/dev/null" "")
    
    # Fallback to PVC if PV lookup fails
    if [ -z "$pvc_size" ]; then
        pvc_size=$(run_kubectl "get pvc minio-pvc -n minio -o jsonpath='{.status.capacity.storage}'")
    fi
    
    if [ -z "$USED" ]; then USED="0"; fi
    
    # Calculate Percentage
    pvc_bytes=$(echo "$pvc_size" | sed 's/i//g' | numfmt --from=iec)
    min_kb=$(echo "$MIN_USAGE" | awk '{print $1}')
    if [ -z "$min_kb" ]; then min_kb=0; fi
    min_bytes=$((min_kb)) # du -b returns bytes
    
    if [ "$pvc_bytes" -gt 0 ]; then
        pct=$((min_bytes * 100 / pvc_bytes))
    else
        pct=0
    fi

    echo -e "\n   ${BOLD}Volume Usage (Container):${NC}"
    printf "   %-20s: %s / %s (%s%%)\n" "Usage" "$(fmt_size $MIN_USAGE)" "$pvc_size" "$pct"
    
    # List Buckets - Recursive Size using du
    echo -e "\n   ${BOLD}Buckets:${NC}"
    # Use du -sh on directories in /export or /data
    BUCKET_STATS=$(exec_capture "kubectl exec -n minio $MINIO_POD -- sh -c 'cd /export 2>/dev/null || cd /data; du -sh * 2>/dev/null'" "")
    
    if [ -n "$BUCKET_STATS" ]; then
        echo "$BUCKET_STATS" | awk '{printf "   • %-20s (%s)\n", $2, $1}'
    else
        echo "   (No buckets found)"
    fi
    
    # Check for PVC attached to pod (generic)
    MIN_PVC=$(exec_capture "kubectl get pod -n minio $MINIO_POD -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim)].persistentVolumeClaim.claimName}' 2>/dev/null | head -n 1" "")
    
    if [ -z "$MIN_PVC" ]; then 
        MIN_PVC="minio-pvc" # Fallback
    fi
 
    print_pv_stats "minio" "$MIN_PVC" "$USED"
fi
echo ""

# --- SECTION 6: KUBECOST (Cost Optimization) ---
print_section_header "KUBECOST (Cost Optimization)" "💰"
KC_POD=$(exec_capture "kubectl get pods -n kubecost -l app=prometheus,component=server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true" "Finding Kubecost Pod")

if [ -z "$KC_POD" ]; then
    echo -e "   ${RED}❌ Pod not found${NC}"
else
    # Disk Usage
    # Remove trailing slash for safety
    KC_USAGE=$(exec_capture "kubectl exec -n kubecost $KC_POD -c prometheus-server -- df -P -B1 /data | grep '/data' | head -n 1" "Checking Disk Usage")
    USED=$(echo "$KC_USAGE" | awk '{print $3}')
    TOTAL=$(echo "$KC_USAGE" | awk '{print $2}')
    PCT=$(echo "$KC_USAGE" | awk '{print $5}')
    
    # Safety
    if [ -z "$USED" ]; then USED="0"; fi

    echo -e "\n   ${BOLD}Volume Usage (Container):${NC}"
    printf "   %-20s: %s / %s (%s)\n" "Usage" "$(fmt_size $USED)" "$(fmt_size $TOTAL)" "$PCT"
    
    # Top Consumers in Prometheus
    echo -e "\n   ${BOLD}Top Consumers:${NC}"
    KC_TOP=$(exec_capture "kubectl exec -n kubecost $KC_POD -c prometheus-server -- sh -c 'du -ah /data | sort -rh | head -n 5' 2>/dev/null" "")
    if [ -n "$KC_TOP" ]; then
         echo "$KC_TOP" | awk '{printf "   %-10s %s\n", $1, $2}'
    fi

    # PV Stats
    print_pv_stats "kubecost" "kubecost-prometheus-server" "$USED"
fi
echo ""

# --- SECTION 7: NEXUS (Artifact Registry) ---
print_section_header "NEXUS (Artifact Registry)" "📦"
NEXUS_POD=$(exec_capture "kubectl get pods -n nexus -l app=nexus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true" "Finding Nexus Pod")

if [ -z "$NEXUS_POD" ]; then
    echo -e "   ${RED}❌ Pod not found${NC}"
else
    # Disk Usage
    NEX_USAGE=$(exec_capture "kubectl exec -n nexus $NEXUS_POD -- df -P -B1 /nexus-data | grep '/nexus-data' | head -n 1" "Checking Disk Usage")
    USED=$(echo "$NEX_USAGE" | awk '{print $3}')
    TOTAL=$(echo "$NEX_USAGE" | awk '{print $2}')
    PCT=$(echo "$NEX_USAGE" | awk '{print $5}')
    
    # Safety
    if [ -z "$USED" ]; then USED="0"; fi

    echo -e "\n   ${BOLD}Volume Usage (Container):${NC}"
    printf "   %-20s: %s / %s (%s)\n" "Usage" "$(fmt_size $USED)" "$(fmt_size $TOTAL)" "$PCT"

    # Nexus Directories (Blobs, DB, ES)
    echo -e "\n   ${BOLD}Directories:${NC}"
    # Use sh -c to check key directories
    DIR_STATS=$(exec_capture "kubectl exec -n nexus $NEXUS_POD -- sh -c 'du -sh /nexus-data/blobs /nexus-data/db /nexus-data/elasticsearch' 2>/dev/null" "Checking Directories")
    
    if [ -n "$DIR_STATS" ]; then
         echo "$DIR_STATS" | awk '{printf "   • %-18s (%s)\n", $2, $1}' | sed 's|/nexus-data/||g'
    else
         echo "   (No directories found)"
    fi

    # PV Stats
    print_pv_stats "nexus" "nexus-pvc" "$USED"
fi
echo ""


# --- SECTION 8: BACKUP & ARCHIVING (Lifecycle) ---
print_section_header "BACKUP & ARCHIVING (Lifecycle)" "🛡️"

run_remote_stats() {
    local target_path="$1"
    ssh "$MASTER_NODE" "bash -s" -- "$target_path" <<'EOF'
        path="$1"
        if [ -d "$path" ]; then
            count=$(find "$path" -type f | wc -l)
            size=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
            newest=$(find "$path" -type f -printf "%T@ %Ty-%Tm-%Td %TH:%TM\n" 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)
            oldest=$(find "$path" -type f -printf "%T@ %Ty-%Tm-%Td %TH:%TM\n" 2>/dev/null | sort -n | head -n 1 | cut -d' ' -f2-)
            [ -z "$newest" ] && newest="N/A"
            [ -z "$oldest" ] && oldest="N/A"
            echo "$count|$size|$newest|$oldest"
        else
            echo "DIR_NOT_FOUND"
        fi
EOF
}

printf "   • %-50s " "Auditing Local Backups..." >&2
ETCD_STATS=$(run_remote_stats "/data/minio/k8s-backups/etcd")
LH_STATS=$(run_remote_stats "/data/minio/k8s-backups/backupstore")
echo -e "${GREEN}DONE${NC}" >&2

# Table for Backups
echo -e "\n   ${BOLD}Repository Status:${NC}"
printf "   ${GRAY}%-20s %-15s %-10s %-25s${NC}\n" "SOURCE" "SIZE" "FILES" "OLDEST -> NEWEST"
echo "   ──────────────────────────────────────────────────────────────────────────"

# Etcd Row
if [[ "$ETCD_STATS" == *"DIR_NOT_FOUND"* ]]; then
    printf "   %-20s ${RED}%-15s${NC}\n" "Etcd (Minio)" "NOT FOUND"
else
    IFS='|' read -r cnt size new old <<< "$ETCD_STATS"
    printf "   %-20s %-15s %-10s %s -> %s\n" "Etcd (Minio)" "$size" "$cnt" "$old" "$new"
fi

# Longhorn Row
if [[ "$LH_STATS" == *"DIR_NOT_FOUND"* ]]; then
     printf "   %-20s ${RED}%-15s${NC}\n" "Longhorn (Minio)" "NOT FOUND"
else
     IFS='|' read -r cnt size new old <<< "$LH_STATS"
     printf "   %-20s %-15s %-10s %s\n" "Longhorn (Minio)" "$size" "N/A" "(Internal Repo)"
fi

# Cloud Row
echo ""
printf "   • %-50s " "Checking Google Drive Sync..." >&2
SYNC_LOG=$(ssh "$MASTER_NODE" "sudo tail -n 1 /var/log/gdrive-sync.log 2>/dev/null")
SYNC_ACTIVE=$(ssh "$MASTER_NODE" "sudo systemctl is-active gdrive-sync.timer")
echo -e "${GREEN}DONE${NC}" >&2

echo -e "   ${BOLD}Cloud Synchronization (GDrive):${NC}"
if [ "$SYNC_ACTIVE" == "active" ]; then
    printf "   %-20s: ${GREEN}Active (Timer Enabled)${NC}\n" "Status"
else
    printf "   %-20s: ${RED}Inactive${NC}\n" "Status"
fi
printf "   %-20s: %s\n" "Last Activity" "$(echo "$SYNC_LOG" | cut -c 1-20)"
printf "   %-20s: " "Latest Log"
echo -e "${GRAY}$(echo "$SYNC_LOG" | cut -d ' ' -f 3- | cut -c 1-60)...${NC}"

echo -e "\n${BLUE}══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Report Generation Complete.${NC}"
echo -e "\n${BOLD}📄 Detailed HTML Report:${NC} http://localhost:8000/inventory.html"
echo -e "${GRAY}   (Updating report in background...)${NC}"

# Trigger HTML Generation & Server Refresh
# Removed background execution to provide foreground feedback and skip stale state
"$SCRIPT_DIR/scripts/observability/generate_inventory_report.sh"

# Play Sound (User Request)
if type alert_sound >/dev/null 2>&1; then
    alert_sound
fi
