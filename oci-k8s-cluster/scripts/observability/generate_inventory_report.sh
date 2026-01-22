#!/bin/bash
# ------------------------------------------------------------------------------
# 🏥 K8s Comprehensive Storage Inventory & Audit Report
# ------------------------------------------------------------------------------
# - Parallel Execution (Map-Reduce)
# - Multi-format Output (Terminal, Markdown, HTML)
# - Scans: K8s PV/PVC, Minio, GDrive, Orphans
# ------------------------------------------------------------------------------

set -e

# --- Configuration ---
# Configuration
MASTER_NODE="oci-k8s-master"
CLUSTER_NODES=("oci-k8s-master" "oci-k8s-node-1" "oci-k8s-node-2" "oci-k8s-node-3")

OUTPUT_DIR="./reports/inventory_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
TEMP_DIR=$(mktemp -d)
# Trap removed for debugging, but we should clean up eventually
# trap "rm -rf $TEMP_DIR" EXIT

# Fetch Backup Policies (RecurringJobs & CronJobs)
echo -e "   [master] Fetching Backup Policies..."
ssh -T -o StrictHostKeyChecking=no "$MASTER_NODE" "kubectl get recurringjobs -n longhorn-system -o json > /tmp/recurring_jobs.json && kubectl get cronjobs -A -o json > /tmp/cron_jobs.json"
scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/recurring_jobs.json" "$TEMP_DIR/recurring_jobs.json"
scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/recurring_jobs.json" "$TEMP_DIR/recurring_jobs.json"
scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/cron_jobs.json" "$TEMP_DIR/cron_jobs.json"

# Fetch Compute Metrics (Usage, Capacity, Pods)
echo -e "   [master] Fetching Compute Metrics..."
ssh -T -o StrictHostKeyChecking=no "$MASTER_NODE" "kubectl top nodes --no-headers > /tmp/nodes_usage.txt && kubectl get nodes -o json > /tmp/nodes_capacity.json && kubectl get pods -A -o json > /tmp/pods_resources.json"
scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/nodes_usage.txt" "$TEMP_DIR/nodes_usage.txt"
scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/nodes_capacity.json" "$TEMP_DIR/nodes_capacity.json"
scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/pods_resources.json" "$TEMP_DIR/pods_resources.json"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

echo -e "${BLUE}${BOLD}🚀 Starting Comprehensive Storage Inventory...${NC}"

# ------------------------------------------------------------------------------
# 1. ORPHAN & SYSTEM SCAN (Parallel)
# ------------------------------------------------------------------------------
scan_node() {
    local node=$1
    echo -e "   [${node}] Spawning scan..."
    
    # Remote script to run on each node
    # Scans for:
    # 1. Large files (>100MB) in non-standard paths (Orphans)
    # 2. Disk Usage Summary
    ssh -T -o StrictHostKeyChecking=no -o ConnectTimeout=45 "$node" "bash -s" <<'EOF' > "$2" 2>/dev/null &
    # 3. Deep Dive Analysis
    echo "--- SYSTEM_TOP ---"
    du -xSh / 2>/dev/null | grep -vE '/var/lib/docker|/var/lib/containerd|/var/lib/longhorn|/var/lib/etcd|/var/backup|/data' | sort -rh | head -n 10 | awk '{print $1, substr($2, length($2)-50)}' || echo "Error scanning system"

    echo "--- DOCKER_TOP ---"
    du -xSh /var/lib/docker /var/lib/containerd 2>/dev/null | sort -rh | head -n 10 | awk '{print $1, substr($2, length($2)-50)}' || echo "Error scanning docker"
    
    echo "--- LOGS_STATS ---"
    journalctl --disk-usage 2>/dev/null || echo "Journal access denied"
    echo "--- RECENT_ERRORS ---"
    journalctl -p 3 -xb | tail -n 5 || echo "No recent errors"
    
    HOSTNAME=$(hostname)
    echo "--- NODE: $HOSTNAME ---"
    
    # 1. Detailed Disk Usage (Matches TUI Dossier Logic)
    # Calculate bytes for precision subtraction
    df_root=$(df -P / | tail -n 1)
    root_used=$(echo "$df_root" | awk '{print $3}')
    root_total=$(echo "$df_root" | awk '{print $2}') # 1k blocks
    root_pct=$(echo "$df_root" | awk '{print $5}')
    
    # Helper to clean du output
    get_size() {
        sudo du -s "$1" 2>/dev/null | cut -f1 || echo "0"
    }

    lh=$(get_size "/var/lib/longhorn")
    
    snap=$(get_size "/var/lib/snapd")
    oracle=$(get_size "/var/lib/oracle-cloud-agent")

    # Sum Docker (Legacy) + Containerd (Runtime)
    cont_d=$(get_size "/var/lib/docker")
    cont_c=$(get_size "/var/lib/containerd")
    cont=$((cont_d + cont_c))
    
    logs=$(get_size "/var/log")
    
    etcd="0"
    [ -d "/var/lib/etcd" ] && etcd=$(get_size "/var/lib/etcd")
    
    backup="0"
    [ -d "/var/backup" ] && backup=$(get_size "/var/backup")
    
    # Minio HostPath (Deduct from System to avoid double counting)
    minio="0"
    [ -d "/data/minio" ] && minio=$(get_size "/data/minio")
    
    # System = Used - (Known Components)
    known=$((lh + snap + oracle + cont + logs + etcd + backup + minio))
    system=$((root_used - known))
    if [ "$system" -lt 0 ]; then system=0; fi
    
    # Output raw values (1k blocks) for report generator to format
    # Format: STATS|PCT|TOTAL|USED|LH|SNAP|ORACLE|DOCKER|LOGS|ETCD|BACKUP|SYSTEM|MINIO
    echo "STATS|$root_pct|$root_total|$root_used|$lh|$snap|$oracle|$cont|$logs|$etcd|$backup|$system|$minio"
    
    # 2. Orphans (Archives/DBs > 50MB in random places)
    # Exclude /var/lib/kubelet, /var/lib/docker/overlay2, /proc, /sys
    # Exclude legitimate backup path: /data/minio/k8s-backups
    echo "--- ORPHANS ---"
    sudo find /home /root /tmp /var/backups /data \
        -type f \
        \( -name "*.tar.gz" -o -name "*.zip" -o -name "*.sql" -o -name "*.db" -o -name "*.bak" -o -name "*.tar" \) \
        -size +50M \
        -not -path "/proc/*" \
        -not -path "/sys/*" \
        -not -path "/run/*" \
        -not -path "/var/lib/docker/*" \
        -not -path "*/overlay2/*" \
        -not -path "*/containers/*" \
        -not -path "/var/lib/kubelet/*" \
        -not -path "/var/lib/containerd/*" \
        -not -path "/var/lib/longhorn/*" \
        -not -path "/data/minio/k8s-backups/*" \
        -exec ls -lh {} \; 2>/dev/null | awk '{print $5, $9}' || echo "None"
        
EOF
    echo $!
}

PIDS=()
echo -e "${YELLOW}📡 Scanning Cluster Nodes (Parallel)...${NC}"
for node in "${CLUSTER_NODES[@]}"; do
    scan_node "$node" "$TEMP_DIR/$node.txt"
    PIDS+=($!)
done

# ------------------------------------------------------------------------------
# 2. K8S & MINIO SCAN (Local/Master)
# ------------------------------------------------------------------------------
echo -e "${YELLOW}☸️  Scanning Kubernetes & Minio...${NC}"

# K8s PVs
ssh -T -o StrictHostKeyChecking=no oci-k8s-master "kubectl get pv -o json" > "$TEMP_DIR/pvs.json"
ssh -T -o StrictHostKeyChecking=no oci-k8s-master "kubectl get pvc --all-namespaces -o json" > "$TEMP_DIR/pvcs.json"

# Minio (Remote exec to Master since it has local mount /data/minio)
# Use max-depth 2 to get Buckets (depth 1) and their Subfolders (depth 2)
ssh -T -o StrictHostKeyChecking=no oci-k8s-master "sudo du -h --max-depth=2 /data/minio 2>/dev/null" > "$TEMP_DIR/minio_usage.txt" &
PIDS+=($!)

# ------------------------------------------------------------------------------
# 3. GDRIVE AUDIT (Remote rclone on Master)
# ------------------------------------------------------------------------------
echo -e "${YELLOW}☁️  Auditing Google Drive...${NC}"
# Use rclone size for accurate sizing AND file count
# Also list subdirectories (lsd) for better visibility
# Output format: FOLDER|SIZE|COUNT|SUBFOLDERS
ssh -T -o StrictHostKeyChecking=no oci-k8s-master "sudo rclone lsd gdrive:k8s-backups --config /root/.config/rclone/rclone.conf | awk '{print \$5}' | while read folder; do 
    size_json=\$(sudo rclone size gdrive:k8s-backups/\$folder --config /root/.config/rclone/rclone.conf --json); 
    bytes=\$(echo \$size_json | jq .bytes | numfmt --to=iec); 
    count=\$(echo \$size_json | jq .count); 
    subfolders=\$(sudo rclone lsd gdrive:k8s-backups/\$folder --config /root/.config/rclone/rclone.conf | awk '{print \$5}' | tr '\n' ', ' | sed 's/, $//'); 
    echo \"\$folder|\$bytes|\$count|\$subfolders\"; 
done" > "$TEMP_DIR/gdrive_usage.txt" 2>&1 &
PIDS+=($!)

# Deep dive: backupstore/volumes breakdown (GDrive)
ssh -T -o StrictHostKeyChecking=no oci-k8s-master "sudo rclone lsd gdrive:k8s-backups/backupstore/volumes --config /root/.config/rclone/rclone.conf | awk '{print \$5}' | while read vol; do 
    size_json=\$(sudo rclone size gdrive:k8s-backups/backupstore/volumes/\$vol --config /root/.config/rclone/rclone.conf --json); 
    bytes=\$(echo \$size_json | jq .bytes | numfmt --to=iec); 
    count=\$(echo \$size_json | jq .count); 
    echo \"\$vol|\$bytes|\$count\"; 
done" > "$TEMP_DIR/gdrive_backupstore_volumes.txt" 2>&1 &
PIDS+=($!)

# Deep dive: backupstore/volumes breakdown (Minio)
ssh -T -o StrictHostKeyChecking=no oci-k8s-master "sudo du -sh /data/minio/k8s-backups/backupstore/volumes/* 2>/dev/null" > "$TEMP_DIR/minio_backupstore_volumes.txt" &
PIDS+=($!)

# Extract Longhorn metadata from Minio backupstore
ssh -T -o StrictHostKeyChecking=no oci-k8s-master 'bash -s' <<'METADATA_SCRIPT' > "$TEMP_DIR/minio_volume_metadata.txt" 2>&1 &
for vol_dir in /data/minio/k8s-backups/backupstore/volumes/*/; do
    vol_hash=$(basename "$vol_dir")
    # Find the first PVC directory inside (usually only one)
    pvc_meta=$(find "$vol_dir" -name "volume.cfg" -type d | head -n 1)
    if [ -n "$pvc_meta" ]; then
        # Extract JSON from xl.meta binary file
        json=$(cat "$pvc_meta/xl.meta" | tr -d '\000' | grep -oP '\{.*\}' 2>/dev/null)
        if [ -n "$json" ]; then
            pvc_name=$(echo "$json" | jq -r '.Labels.KubernetesStatus' | jq -r '.pvcName' 2>/dev/null)
            namespace=$(echo "$json" | jq -r '.Labels.KubernetesStatus' | jq -r '.namespace' 2>/dev/null)
            created=$(echo "$json" | jq -r '.CreatedTime' 2>/dev/null)
            last_backup=$(echo "$json" | jq -r '.LastBackupAt' 2>/dev/null)
            size=$(echo "$json" | jq -r '.Size' 2>/dev/null | numfmt --to=iec 2>/dev/null)
            
            # Count snapshot configs (backup_*.cfg)
            snap_count=$(find "$vol_dir" -name "backup_*.cfg" | wc -l)
            
            echo "$vol_hash|$pvc_name|$namespace|$created|$last_backup|$size|$snap_count"
        fi
    fi
done
METADATA_SCRIPT
PIDS+=($!)

# Extract Longhorn metadata from GDrive backupstore
ssh -T -o StrictHostKeyChecking=no oci-k8s-master 'bash -s' <<'GDRIVE_METADATA_SCRIPT' > "$TEMP_DIR/gdrive_volume_metadata.txt" 2>&1 &
for vol in $(sudo rclone lsd gdrive:k8s-backups/backupstore/volumes --config /root/.config/rclone/rclone.conf | awk '{print $5}'); do
    # Download volume.cfg/xl.meta from GDrive
    pvc_path=$(sudo rclone lsf gdrive:k8s-backups/backupstore/volumes/$vol --dirs-only --config /root/.config/rclone/rclone.conf | head -n 1 | sed 's|/$||')
    if [ -n "$pvc_path" ]; then
        sudo rclone cat "gdrive:k8s-backups/backupstore/volumes/$vol/$pvc_path/volume.cfg/xl.meta" --config /root/.config/rclone/rclone.conf 2>/dev/null | tr -d '\000' | grep -oP '\{.*\}' | head -n 1 > /tmp/vol_meta_$vol.json 2>/dev/null
        if [ -s /tmp/vol_meta_$vol.json ]; then
            pvc_name=$(jq -r '.Labels.KubernetesStatus' /tmp/vol_meta_$vol.json | jq -r '.pvcName' 2>/dev/null)
            namespace=$(jq -r '.Labels.KubernetesStatus' /tmp/vol_meta_$vol.json | jq -r '.namespace' 2>/dev/null)
            created=$(jq -r '.CreatedTime' /tmp/vol_meta_$vol.json 2>/dev/null)
            last_backup=$(jq -r '.LastBackupAt' /tmp/vol_meta_$vol.json 2>/dev/null)
            size=$(jq -r '.Size' /tmp/vol_meta_$vol.json 2>/dev/null | numfmt --to=iec 2>/dev/null)
            
            echo "$vol|$pvc_name|$namespace|$created|$last_backup|$size"
            rm -f /tmp/vol_meta_$vol.json
        fi
    fi
done
GDRIVE_METADATA_SCRIPT
PIDS+=($!)


# Extract Detailed Snapshot Data (Minio) - SYNCHRONOUS
echo -e "${BLUE}📸 Extracting Snapshot Details...${NC}"
ssh -T -o StrictHostKeyChecking=no oci-k8s-master 'bash -s' <<'SNAPSHOT_SCRIPT' > "$TEMP_DIR/minio_snapshot_details.txt" 2>&1
find /data/minio/k8s-backups/backupstore/volumes -path "*/backups/*/xl.meta" -type f 2>/dev/null | while read meta; do
    # Extract Volume Hash: /data/.../volumes/<HASH>/<PVC_UID>/backups/...
    vol_hash=$(echo "$meta" | awk -F'/' '{print $7}')
    
    # Safe Binary Extract
    json=$(cat "$meta" | tr -d '\000' | grep -oP '\{.*\}' | head -n 1)
    
    if [ -n "$json" ]; then
        s_date=$(echo "$json" | jq -r '.SnapshotCreatedAt' 2>/dev/null)
        s_size=$(echo "$json" | jq -r '.Size' 2>/dev/null)
        
        if [ "$s_date" != "null" ]; then
             echo "$vol_hash|$s_date|$s_size"
        fi
    fi
done
SNAPSHOT_SCRIPT

# Verify Extraction
line_count=$(wc -l < "$TEMP_DIR/minio_snapshot_details.txt" 2>/dev/null || echo 0)
echo "DEBUG: Extracted $line_count snapshot records" >> /tmp/report_debug.log
# ------------------------------------------------------------------------------
# 4. WAIT FOR RESULTS
# ------------------------------------------------------------------------------
echo -e "${BLUE}⏳ Waiting for tasks to complete...${NC}"
set +e
for pid in "${PIDS[@]}"; do
    wait "$pid"
done
set -e
echo -e "${GREEN}✅ Data Collection Complete.${NC}"

# ------------------------------------------------------------------------------
# 5. GENERATE REPORT (Markdown)
# ------------------------------------------------------------------------------
MD_FILE="$OUTPUT_DIR/inventory.md"
HTML_FILE="$OUTPUT_DIR/inventory.html"

{
    echo "# 🏥 Storage Inventory Report"
    echo ""
    
    echo "## 1. Cloud Backup (Google Drive)"
    echo "| Folder | Real Size | Files | Contents (Subfolders) | Status |"
    echo "|---|---|---|---|---|"
    if [ -s "$TEMP_DIR/gdrive_usage.txt" ]; then
        while IFS='|' read -r folder size count subs; do
            [ -z "$subs" ] && subs="-"
            echo "| **$folder** | $size | $count | \`$subs\` | ✅ Synced |"
            
            # Special handling for backupstore - show volumes breakdown WITH METADATA
            if [ "$folder" = "backupstore" ] && [ -s "$TEMP_DIR/gdrive_backupstore_volumes.txt" ]; then
                # Sort by size (descending) before display
                sort -t'|' -k2 -h -r "$TEMP_DIR/gdrive_backupstore_volumes.txt" > "$TEMP_DIR/gdrive_backupstore_volumes_sorted.txt"
                
                echo "|"
                echo "| 📂 **Backupstore Volumes Breakdown (Longhorn PVCs)** | | | | |"
                echo "|---|---|---|---|---|"
                echo "| Volume | PVC Name | Namespace | Size | Files | Snapshots | Created → Last Backup |"
                echo "|---|---|---|---|---|---|---|"
                while IFS='|' read -r vol vol_size vol_count; do
                    # Try to get metadata for this volume (Use Minio metadata as it shares the same Volume Hash/UUID)
                    if [ -s "$TEMP_DIR/minio_volume_metadata.txt" ]; then
                        meta_line=$(grep "^$vol|" "$TEMP_DIR/minio_volume_metadata.txt" 2>/dev/null)
                        if [ -n "$meta_line" ]; then
                            IFS='|' read -r _ pvc_name namespace created last_backup meta_size snap_count <<< "$meta_line"
                            # Format dates (Readable: Jan 18, 2026)
                            created_short=$(date -d "$created" +'%b %d, %Y' 2>/dev/null || echo "$created")
                            last_backup_short=$(date -d "$last_backup" +'%b %d, %Y' 2>/dev/null || echo "$last_backup")
                            echo "| \`$vol\` | **$pvc_name** | \`$namespace\` | **$meta_size** | $vol_count | $snap_count | $created_short → $last_backup_short |"
                            
                            # Embed Snapshot Details
                            if [ -s "$TEMP_DIR/minio_snapshot_details.txt" ]; then
                                snap_rows=$(grep "^$vol|" "$TEMP_DIR/minio_snapshot_details.txt" | sort -t'|' -k2 -r | head -n 10) # Show top 10 recent
                                if [ -n "$snap_rows" ]; then
                                    echo ""
                                    echo "<details class='node-details'><summary>📜 View Recent Snapshots ($snap_count total)</summary><table class='snapshot-table'>"
                                    echo "<thead><tr><th>Date</th><th>Size</th></tr></thead><tbody>"
                                    while IFS='|' read -r _ s_date s_size; do
                                        s_date_fmt=$(date -d "$s_date" +'%b %d, %Y %H:%M' 2>/dev/null || echo "$s_date")
                                        s_size_fmt=$(numfmt --to=iec "$s_size" 2>/dev/null || echo "$s_size")
                                        echo "<tr><td>$s_date_fmt</td><td>$s_size_fmt</td></tr>"
                                    done <<< "$snap_rows"
                                    echo "</tbody></table></details>"
                                fi
                            fi
                        else
                            echo "| \`$vol\` | - | - | $vol_size | $vol_count | - |"
                        fi
                    else
                        echo "| \`$vol\` | - | - | $vol_size | $vol_count | - |"
                    fi
                done < "$TEMP_DIR/gdrive_backupstore_volumes_sorted.txt"
            fi
        done < "$TEMP_DIR/gdrive_usage.txt"
    else
        echo "| Error | - | - | - | ❌ Unreachable |"
    fi
    echo ""
    
    echo "## 2. Minio Object Storage (Local)"
    echo "| Bucket | Size | Details (Top Subfolders) |"
    echo "|---|---|---|"
    if [ -s "$TEMP_DIR/minio_usage.txt" ]; then
        # Filter out root line (/data/minio) to avoid clutter
        grep -vE "[[:space:]]/data/minio$" "$TEMP_DIR/minio_usage.txt" > "$TEMP_DIR/minio_filtered.txt"
        
        # Identify Buckets (Depth 1 folders directly under /data/minio)
        # Regex explanation: Match path ending with /data/minio/FOLDER_NAME (no extra slashes)
        BUCKETS=$(grep -E "[[:space:]]/data/minio/[^/]+$" "$TEMP_DIR/minio_filtered.txt" | awk '{print $2}' | sort | uniq)
        
        for bucket_path in $BUCKETS; do
             bucket_name=$(basename "$bucket_path")
             # Retrieve size for this bucket
             bucket_size=$(grep -F "$bucket_path" "$TEMP_DIR/minio_filtered.txt" | head -n1 | awk '{print $1}')
             
             # Find subfolders for this bucket (lines containing bucket path + / + subfolder)
             # awk formats as: subfolder(size)
             subs_clean=$(grep -F "$bucket_path/" "$TEMP_DIR/minio_filtered.txt" | awk -v p="$bucket_path/" '{sub(p, "", $2); sub("^/", "", $2); print $2 " (" $1 ")"}' | tr '\n' ', ' | sed 's/, $//')
             
             [ -z "$subs_clean" ] && subs_clean="-"
             
             echo "| **$bucket_name** | $bucket_size | $subs_clean |"
             
             # Special handling for k8s-backups/backupstore - show volumes breakdown WITH METADATA
             if [ "$bucket_name" = "k8s-backups" ] && [ -s "$TEMP_DIR/minio_backupstore_volumes.txt" ]; then
                 # Sort by size (descending) before display
                 sort -k1 -h -r "$TEMP_DIR/minio_backupstore_volumes.txt" > "$TEMP_DIR/minio_backupstore_volumes_sorted.txt"
                 
                 echo "|"
                 echo "| 📂 **k8s-backups/backupstore/volumes Breakdown (Longhorn PVCs)** | | |"
                 echo "|---|---|---|"
                 echo "| Volume | PVC Name | Namespace | Size | Snapshots | Created → Last Backup |"
                 echo "|---|---|---|---|---|---|"
                 while read -r line; do
                     vol_size=$(echo "$line" | awk '{print $1}')
                     vol_path=$(echo "$line" | awk '{print $2}')
                     vol_name=$(basename "$vol_path")
                     
                     # Try to get metadata for this volume
                     echo "DEBUG: Checking $vol_name in $TEMP_DIR/minio_volume_metadata.txt" >> /tmp/report_debug.log
                     if [ -s "$TEMP_DIR/minio_volume_metadata.txt" ]; then
                         meta_line=$(grep "^$vol_name|" "$TEMP_DIR/minio_volume_metadata.txt")
                         echo "DEBUG: Result: $meta_line" >> /tmp/report_debug.log
                         if [ -n "$meta_line" ]; then
                             IFS='|' read -r _ pvc_name namespace created last_backup meta_size snap_count <<< "$meta_line"
                             # Format dates (Readable: Jan 18, 2026)
                             created_short=$(date -d "$created" +'%b %d, %Y' 2>/dev/null || echo "$created")
                             last_backup_short=$(date -d "$last_backup" +'%b %d, %Y' 2>/dev/null || echo "$last_backup")
                             echo "| \`$vol_name\` | **$pvc_name** | \`$namespace\` | **$meta_size** | $snap_count | $created_short → $last_backup_short |"
                             
                             # Embed Snapshot Details
                             if [ -s "$TEMP_DIR/minio_snapshot_details.txt" ]; then
                                 snap_rows=$(grep "^$vol_name|" "$TEMP_DIR/minio_snapshot_details.txt" | sort -t'|' -k2 -r | head -n 10)
                                 if [ -n "$snap_rows" ]; then
                                     echo ""
                                     echo "<details class='node-details'><summary>📜 View Recent Snapshots ($snap_count total)</summary><table class='snapshot-table'>"
                                     echo "<thead><tr><th>Date</th><th>Size</th></tr></thead><tbody>"
                                     while IFS='|' read -r _ s_date s_size; do
                                         s_date_fmt=$(date -d "$s_date" +'%b %d, %Y %H:%M' 2>/dev/null || echo "$s_date")
                                         s_size_fmt=$(numfmt --to=iec "$s_size" 2>/dev/null || echo "$s_size")
                                         echo "<tr><td>$s_date_fmt</td><td>$s_size_fmt</td></tr>"
                                     done <<< "$snap_rows"
                                     echo "</tbody></table></details>"
                                 fi
                             fi
                         else
                             echo "| \`$vol_name\` | - | - | $vol_size | - |"
                         fi
                     else
                         echo "DEBUG: Metadata file empty or missing" >> /tmp/report_debug.log
                         echo "| \`$vol_name\` | - | - | $vol_size | - |"
                     fi
                 done < "$TEMP_DIR/minio_backupstore_volumes_sorted.txt"
             fi
        done
    else
         echo "| No Data | - | - |"
    fi
    echo ""

    echo "## 3. Node Inventory & Orphans (Potential Cleanup)"
    echo "> **Note:** Scans directories: /home, /root, /tmp, /data. Excludes active backups."
    echo ""
    
    # Table Header
    echo "| Node | Usage | Size | Longhorn | Snap | Oracle | Docker | Logs | Etcd | Backup | System |"
    echo "|---|---|---|---|---|---|---|---|---|---|---|"
    
    for node in "${CLUSTER_NODES[@]}"; do
        if [ -f "$TEMP_DIR/$node.txt" ]; then
            # Parse STATS line
            stats_line=$(grep "^STATS|" "$TEMP_DIR/$node.txt" || echo "")
            
            if [ -n "$stats_line" ]; then
                 IFS='|' read -r _tag pct total used lh snap oracle cont logs etcd backup system minio <<< "$stats_line"
                 
                 # Helper to format kilobytes to human
                 fmt_kb() {
                     numfmt --to=iec --from-unit=1024 "$1" 2>/dev/null || echo "0B"
                 }
                 
                 # Default values to 0 to prevent JS syntax errors
                 lh=${lh:-0}
                 snap=${snap:-0}
                 oracle=${oracle:-0}
                 cont=${cont:-0}
                 logs=${logs:-0}
                 etcd=${etcd:-0}
                 backup=${backup:-0}
                 system=${system:-0}
                 minio=${minio:-0}
                 
                 h_total=$(fmt_kb "$total")
                 h_lh=$(fmt_kb "$lh")
                 h_snap=$(fmt_kb "$snap")
                 h_oracle=$(fmt_kb "$oracle")
                 h_cont=$(fmt_kb "$cont")
                 h_logs=$(fmt_kb "$logs")
                 [ "$etcd" -gt 0 ] && h_etcd=$(fmt_kb "$etcd") || h_etcd="-"
                 [ "$backup" -gt 0 ] && h_backup=$(fmt_kb "$backup") || h_backup="-"
                 h_system=$(fmt_kb "$system")
                 
                 # Status Icon based on PCT
                 clean_pct=${pct%\%}
                 status_icon="🟢"
                 if [ "$clean_pct" -gt 85 ]; then status_icon="🔴"; elif [ "$clean_pct" -gt 70 ]; then status_icon="🟡"; fi
                 
                 echo "| **$node** | $status_icon $pct | $h_total | $h_lh | $h_snap | $h_oracle | $h_cont | $h_logs | $h_etcd | $h_backup | $h_system |"
                 
                 # Save for Charts (Raw Bytes)
                 # Format: NODE|TOTAL|USED|LH|SNAP|ORACLE|CONT|LOGS|ETCD|BACKUP|SYSTEM|MINIO
                 echo "$node|$total|$used|$lh|$snap|$oracle|$cont|$logs|$etcd|$backup|$system|$minio" >> "$TEMP_DIR/charts.dat"
                 
                 # --- DEEP DIVE GENERATION ---
                 sys_top=$(sed -n '/--- SYSTEM_TOP ---/,/--- DOCKER_TOP ---/p' "$TEMP_DIR/$node.txt" | grep -v "\-\-\-" | grep -v "Error" | head -n 10)
                 dock_top=$(sed -n '/--- DOCKER_TOP ---/,/--- LOGS_STATS ---/p' "$TEMP_DIR/$node.txt" | grep -v "\-\-\-" | grep -v "Error" | head -n 10)
                 
                 # Only show if there is data
                 if [ -n "$sys_top" ] || [ -n "$dock_top" ]; then
                     detail_html="<div class='deep-dive-section'>"
                     
                     if [ -n "$sys_top" ]; then
                         detail_html+="<div class='deep-dive-title'>❌ High System Usage</div><ul class='deep-list'>"
                         while read -r line; do
                             if [ -n "$line" ]; then
                                 size=$(echo "$line" | awk '{print $1}')
                                 path=$(echo "$line" | cut -d' ' -f2-)
                                 detail_html+="<li class='deep-item'><span class='deep-size'>$size</span><span class='deep-path ctx-system'>$path</span></li>"
                             fi
                         done <<< "$sys_top"
                         detail_html+="</ul>"
                     fi
                     
                     if [ -n "$dock_top" ]; then
                         detail_html+="<div class='deep-dive-title' style='margin-top:15px'>🐳 Top Docker Layers</div><ul class='deep-list'>"
                         while read -r line; do
                             if [ -n "$line" ]; then
                                 size=$(echo "$line" | awk '{print $1}')
                                 path=$(echo "$line" | cut -d' ' -f2-)
                                 # Contextualize path
                                 ctx=""
                                 if [[ "$path" == *"/diff/"* ]]; then ctx=" (Layer)"; fi
                                 if [[ "$path" == *"-json.log"* ]]; then ctx=" (Logs)"; fi
                                 
                                 detail_html+="<li class='deep-item'><span class='deep-size'>$size</span><span class='deep-path ctx-docker'>$path$ctx</span></li>"
                             fi
                         done <<< "$dock_top"
                         detail_html+="</ul>"
                     fi
                     
                     detail_html+="</div>"
                     # Inject as Detail Row
                     echo "+ $detail_html"
                 fi
                 
            else
                 echo "| **$node** | ❌ Error | - | - | - | - | - | - | - |"
            fi
            
            # Orphans in separate block (Legacy, keep or move?)
            # Let's keep Orphans as they are large file warnings outside the summary
            
            # Orphans in separate block
            echo ""
            echo "**$node - Large Orphan Files (>50MB):**"
            echo "\`\`\`"
            sed -n '/--- ORPHANS ---/,$p' "$TEMP_DIR/$node.txt" | tail -n +2 || echo "None"
            echo "\`\`\`"
        fi
        echo ""
    done
    
    echo "## 4. Kubernetes Volumes (PVCs)"
    echo "| Namespace | Name | Status | Size | Volume |"
    echo "|---|---|---|---|---|"
    # Parse JSON, normalize size variants (e.g. 2254857830400m -> 2.1Ti)
    jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.status.phase) \(.spec.resources.requests.storage) \(.spec.volumeName)"' "$TEMP_DIR/pvcs.json" | \
    while read ns name phase size vol; do
        if [[ "$size" == *"m" ]]; then
            # Handle milli-bytes (e.g. 2254857830400m)
            # Remove 'm', divide by 1000 to get bytes
            bytes=$(echo "$size" | sed 's/m//')
            size_human=$(echo $((bytes / 1000)) | numfmt --to=iec)
        else
            # Request is likely already friendly (e.g. 10Gi) or raw bytes
            size_human=$size
        fi
        echo "| $ns | $name | $phase | $size_human | $vol |"
        echo "| $ns | $name | $phase | $size_human | $vol |"
    done
    
    echo ""
    echo "## 5. Active Backup Policies"
    echo "| Type | Name | Schedule | Retention | Target/Group |"
    echo "|---|---|---|---|---|"
    
    # 1. Longhorn Recurring Jobs
    if [ -s "$TEMP_DIR/recurring_jobs.json" ]; then
        jq -r '.items[] | "Longhorn|\(.metadata.name)|\(.spec.cron)|\(.spec.retain)|\(.spec.task) (\(.spec.groups[0] // "default"))"' "$TEMP_DIR/recurring_jobs.json" | \
        while IFS='|' read -r type name cron retain details; do
             echo "| **$type** | $name | \`$cron\` | $retain | $details |"
        done
    fi
    
    # 2. System CronJobs (Etcd, Postgres, etc)
    if [ -s "$TEMP_DIR/cron_jobs.json" ]; then
        jq -r '.items[] | "CronJob|\(.metadata.name)|\(.spec.schedule)|-|\(.metadata.namespace)"' "$TEMP_DIR/cron_jobs.json" | \
        while IFS='|' read -r type name cron retain ns; do
             # Filter relevant backup jobs if needed, or show all
             if [[ "$name" == *"backup"* ]] || [[ "$name" == *"snapshot"* ]]; then
                 echo "| **$type** | $name | \`$cron\` | - | $ns |"
             fi
        done
    fi

    # --------------------------------------------------------------------------
    # 6. Compute Resources (CPU/RAM)
    # --------------------------------------------------------------------------
    echo ""
    echo "## 6. Compute Resources (CPU/RAM)"
    echo "| Node | CPU Usage | CPU Req/Lim | Mem Usage | Mem Req/Lim | Status |"
    echo "|---|---|---|---|---|---|"
    
    # Helper to convert to millicores/Mi
    to_milli() {
        val=$1
        if [[ "$val" == *"m" ]]; then echo "${val%m}"; 
        elif [[ "$val" =~ ^[0-9]+$ ]]; then echo "$((val * 1000))";
        else echo "0"; fi
    }
    
    to_mi() {
        val=$1
        if [[ "$val" == *"Ki" ]]; then echo $(( ${val%Ki} / 1024 ));
        elif [[ "$val" == *"Mi" ]]; then echo "${val%Mi}"; 
        elif [[ "$val" == *"Gi" ]]; then echo $(( ${val%Gi} * 1024 ));
        else echo "0"; fi
    }

    if [ -f "$TEMP_DIR/nodes_usage.txt" ] && [ -f "$TEMP_DIR/pods_resources.json" ]; then
        for node in "${CLUSTER_NODES[@]}"; do
            # Usage (from top)
            read -r _ u_cpu u_cpu_pct u_mem u_mem_pct <<< $(grep "$node" "$TEMP_DIR/nodes_usage.txt" || echo "0 0m 0% 0Mi 0%")
            
            # Capacity (from json) - simplified
            # cap_cpu=$(jq -r --arg n "$node" ".items[] | select(.metadata.name==$n) | .status.capacity.cpu" "$TEMP_DIR/nodes_capacity.json")
            # cap_mem=$(jq -r --arg n "$node" ".items[] | select(.metadata.name==$n) | .status.capacity.memory" "$TEMP_DIR/nodes_capacity.json")

            # Requests/Limits (Sum from Pods)
            # Refined jq with fallback to 0 and improved unit parsing
            cpu_stats=$(jq -r --arg n "$node" "[.items[] | select(.spec.nodeName==\$n) | .spec.containers[]?.resources.requests.cpu // \"0\"] | map(if . == \"0\" then 0 elif endswith(\"m\") then (sub(\"m\"; \"\") | tonumber) else (tonumber? * 1000 // 0) end) | add // 0" "$TEMP_DIR/pods_resources.json")
            cpu_lims=$(jq -r --arg n "$node" "[.items[] | select(.spec.nodeName==\$n) | .spec.containers[]?.resources.limits.cpu // \"0\"] | map(if . == \"0\" then 0 elif endswith(\"m\") then (sub(\"m\"; \"\") | tonumber) else (tonumber? * 1000 // 0) end) | add // 0" "$TEMP_DIR/pods_resources.json")
            
            mem_stats=$(jq -r --arg n "$node" "[.items[] | select(.spec.nodeName==\$n) | .spec.containers[]?.resources.requests.memory // \"0\"] | map(if . == \"0\" then 0 elif endswith(\"Gi\") then (sub(\"Gi\"; \"\") | tonumber * 1024) elif endswith(\"Mi\") then (sub(\"Mi\"; \"\") | tonumber) elif endswith(\"Ki\") then (sub(\"Ki\"; \"\") | tonumber / 1024) else 0 end) | add // 0" "$TEMP_DIR/pods_resources.json")
            mem_lims=$(jq -r --arg n "$node" "[.items[] | select(.spec.nodeName==\$n) | .spec.containers[]?.resources.limits.memory // \"0\"] | map(if . == \"0\" then 0 elif endswith(\"Gi\") then (sub(\"Gi\"; \"\") | tonumber * 1024) elif endswith(\"Mi\") then (sub(\"Mi\"; \"\") | tonumber) elif endswith(\"Ki\") then (sub(\"Ki\"; \"\") | tonumber / 1024) else 0 end) | add // 0" "$TEMP_DIR/pods_resources.json")

            # Format (CPU in m, Mem in Mi)
            cpu_req="${cpu_stats}m"
            cpu_lim="${cpu_lims}m"
            mem_req="${mem_stats}Mi"
            mem_lim="${mem_lims}Mi"
            
            # Status Icon (Based on CPU/Mem %)
            c_p=${u_cpu_pct%\%}
            m_p=${u_mem_pct%\%}
            icon="🟢"
            if [ "$c_p" -gt 85 ] || [ "$m_p" -gt 85 ]; then icon="🔴"; elif [ "$c_p" -gt 70 ] || [ "$m_p" -gt 70 ]; then icon="🟡"; fi

            echo "| **$node** | $u_cpu ($u_cpu_pct) | R: $cpu_req / L: $cpu_lim | $u_mem ($u_mem_pct) | R: $mem_req / L: $mem_lim | $icon |"
        done

        # Detailed Pod Breakdown (New Section)
        echo ""
        echo "## 7. Detailed Pod Resource Breakdown"
        echo "| Namespace | Pod Name | CPU Req | Mem Req | Node |"
        echo "|---|---|---|---|---|"
        jq -r ".items[] | \"\(.metadata.namespace)|\(.metadata.name)|\(.spec.containers[]?.resources.requests.cpu // \"0\")|\(.spec.containers[]?.resources.requests.memory // \"0\")|\(.spec.nodeName)\"" "$TEMP_DIR/pods_resources.json" | \
        while IFS='|' read -r ns name cpu mem p_node; do
            echo "| $ns | \`$name\` | $cpu | $mem | $p_node |"
        done
    else
        echo "| Scans failed | - | - | - | - | ❌ |"
    fi
} > "$MD_FILE"

# ------------------------------------------------------------------------------
# 6. CONVERT TO HTML
# ------------------------------------------------------------------------------
# Simple CSS wrapper
cat <<EOF > "$HTML_FILE"
<!DOCTYPE html>
<html lang="en" data-theme="light">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cluster Inventory</title>
    <style>
        :root {
            --bg-body: #f4f4f4;
            --bg-body: #f4f4f4;
            --bg-container: #ffffff;
            --text-main: #333333;
            --text-muted: #999999;
            --border-color: #e1e4e8;
            --header-border: #3498db;
            --th-bg: #eaecf0; /* Darker grey */
            --th-text: #2c3e50;
            --row-even: #f8f9fa;
            --row-hover: #f1f1f1;
            --code-bg: #eeeeee;
        }

        [data-theme="dark"] {
            --bg-body: #1a1a1a;
            --bg-container: #2d2d2d;
            --text-main: #e0e0e0;
            --text-muted: #bdc3c7;
            --border-color: #444444;
            --header-border: #2980b9;
            --th-bg: #404040; /* Lighter dark */
            --th-text: #ffffff;
            --row-even: #363636;
            --row-hover: #404040;
            --code-bg: #444444;
        }

        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; padding: 20px; background: var(--bg-body); color: var(--text-main); transition: background 0.3s; }
        .container { background: var(--bg-container); padding: 30px; border-radius: 8px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); max-width: 1000px; margin: 0 auto; position: relative; }
        
        /* Settings Toggle */
        .settings-panel { position: absolute; top: 20px; right: 20px; display: flex; gap: 10px; }
        .btn-toggle { background: transparent; border: 1px solid var(--border-color); padding: 5px 10px; border-radius: 20px; cursor: pointer; color: var(--text-main); font-size: 1.1em; transition: all 0.2s; }
        .btn-toggle:hover { background: var(--row-hover); transform: scale(1.1); }

        h1 { color: var(--text-main); border-bottom: 2px solid var(--header-border); padding-bottom: 15px; }
        h2 { color: var(--header-border); margin-top: 35px; border-bottom: 1px solid var(--border-color); padding-bottom: 8px; }
        
        /* Tabs */
        .tabs { display: flex; gap: 10px; margin-bottom: 20px; border-bottom: 1px solid var(--border-color); padding-bottom: 15px; }
        .tab-btn { background: transparent; border: none; padding: 10px 20px; font-size: 1.1em; cursor: pointer; color: var(--text-muted); border-radius: 6px; transition: all 0.2s; font-weight: 600; }
        .tab-btn:hover { background: var(--row-hover); color: var(--text-main); }
        .tab-btn.active { background: var(--header-border); color: white; }
        .tab-content { display: none; animation: fadeIn 0.3s; }
        .tab-content.active { display: block; }
        @keyframes fadeIn { from { opacity: 0; transform: translateY(5px); } to { opacity: 1; transform: translateY(0); } }

        h3 { color: var(--text-muted); margin-top: 25px; }

        .snapshot-table { width: auto !important; margin: 10px 0; font-size: 0.9em; }


        table { width: 100%; border-collapse: separate; border-spacing: 0; margin: 20px 0; background: var(--bg-container); border: 1px solid var(--border-color); border-radius: 6px; overflow: hidden; }
        th, td { padding: 12px 15px; border-bottom: 1px solid var(--border-color); text-align: left; }
        th { background: var(--th-bg); color: var(--th-text); font-weight: 700; border-bottom: 2px solid var(--border-color); text-transform: uppercase; font-size: 0.85em; letter-spacing: 0.05em; }
        td { border-right: 1px solid transparent; } /* Clean look */
        tr:nth-child(even) { background: var(--row-even); }
        tr:hover { background-color: var(--row-hover); }

        code { background: var(--code-bg); padding: 3px 6px; border-radius: 4px; font-family: Consolas, monospace; border: 0.5px solid var(--border-color); }
        pre { background: #1e1e1e; color: #f8f8f2; padding: 15px; border-radius: 6px; overflow-x: auto; border: 1px solid #333; }
        
        .timestamp { color: var(--text-muted); font-size: 0.85em; margin-bottom: 10px; display: block; }
        a { color: var(--header-border); text-decoration: none; }
        a:hover { text-decoration: underline; }
        
        /* Sorting Styles */
        th { cursor: pointer; user-select: none; position: relative; }
        th:hover { background: var(--border-color); }
        th::after { content: ''; display: inline-block; margin-left: 5px; width: 0; height: 0; border-left: 4px solid transparent; border-right: 4px solid transparent; vertical-align: middle; opacity: 0.3; }
        th.asc::after { border-bottom: 4px solid currentColor; opacity: 1; }
        th.desc::after { border-top: 4px solid currentColor; opacity: 1; }
        
        /* Chart.js overrides */
        .chart-wrapper { background: var(--bg-container); border: 1px solid var(--border-color); border-radius: 8px; padding: 15px; margin-bottom: 20px; display: flex; align-items: center; justify-content: space-around; flex-wrap: wrap; }
        .chart-canvas-container { position: relative; width: 250px; height: 250px; }
        .chart-legend { margin-left: 20px; min-width: 200px; font-size: 0.9em; }
        .legend-item { display: flex; align-items: center; margin-bottom: 5px; justify-content: space-between; padding: 3px 0; border-bottom: 1px dashed var(--border-color); }
        .legend-color { width: 12px; height: 12px; display: inline-block; margin-right: 8px; border-radius: 2px; }
        .legend-label { font-weight: 500; color: var(--text-main); }
        .legend-value { font-family: Consolas, monospace; color: var(--text-muted); font-weight: bold; }
        .chart-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(500px, 1fr)); gap: 20px; margin-top: 20px; }
        
        /* Deep Dive Styles */
        .deep-dive-section { background: var(--bg-body); border-radius: 6px; padding: 15px; margin-top: 15px; font-size: 0.9em; border: 1px solid var(--border-color); }
        .deep-dive-title { margin: 0 0 10px 0; font-weight: 600; display: flex; align-items: center; gap: 8px; font-size: 0.95em; color: var(--header-border); }
        .deep-list { list-style: none; padding: 0; margin: 0; }
        .deep-item { display: flex; justify-content: space-between; padding: 4px 0; border-bottom: 1px dashed var(--border-color); font-family: Consolas, monospace; }
        .deep-item:last-child { border-bottom: none; }
        .deep-size { font-weight: bold; color: var(--text-muted); min-width: 60px; text-align: right; }
        .deep-path { color: var(--text-main); word-break: break-all; margin-left: 10px; flex: 1; text-align: left; }
        
        /* Specific Context Colors */
        .ctx-system { color: #e67e22; } /* Orange */
        .ctx-docker { color: #3498db; } /* Blue */ 
        .ctx-logs { color: #9b59b6; }   /* Purple */
        
        details.node-details summary { cursor: pointer; color: var(--header-border); font-weight: 600; margin-bottom: 10px; user-select: none; }
        details.node-details summary:hover { text-decoration: underline; }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="container">
        <div class="settings-panel">
             <button class="btn-toggle" onclick="toggleLang()" title="Switch Language">🇧🇷/🇺🇸</button>
             <button class="btn-toggle" onclick="toggleTheme()" title="Toggle Dark Mode">🌙/☀️</button>
        </div>
        <!-- Raw timestamp for JS -->
        <div class="timestamp">
            <span data-original="Generated:">Generated:</span> 
            <span id="report-date" data-timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)">$(date -u)</span>
        </div>
        
        <div class="tabs">
            <button class="tab-btn active" id="btn-tab-storage" onclick="openTab('tab-storage')">Storage</button>
            <button class="tab-btn" id="btn-tab-compute" onclick="openTab('tab-compute')">Compute (CPU/RAM)</button>
        </div>

        </div>
EOF

# Convert MD to basic HTML (Primitive parser for tables and headers)
# Note: For a robust solution, pandoc is better, but this is dependency-free.
sed -E 's/^# (.*)/<h1>\1<\/h1>/' "$MD_FILE" | \
sed -E 's/^## (.*)/<h2>\1<\/h2>/' | \
sed -E 's/^### (.*)/<h3>\1<\/h3>/' | \
sed -E 's/\*\*([^*]+)\*\*/<b>\1<\/b>/g' | \
sed -E 's/`([^`]+)`/<code>\1<\/code>/g' | \
awk '
BEGIN { 
    print "<div id=\"tab-storage\" class=\"tab-content active\">";
    print "<div id=\"chart-section\" style=\"margin-top: 30px; display:none;\">";
    print "<h2>📊 Storage Distribution (Visual)</h2>";
    print "<div id=\"charts-area\" class=\"chart-grid\"></div>";
    print "</div>";
    in_table=0; in_code=0 
}
/<h2>6. Compute Resources/ {
    if (in_table) { print "</table>"; in_table=0 }
    print "</div>"
    print "<div id=\"tab-compute\" class=\"tab-content\">"
    print $0
    next
}
/^```/ { 
    if (in_code) { print "</pre>"; in_code=0 } 
    else { print "<pre>"; in_code=1 } 
    next 
}
/^\|/ { 
    if ($0 ~ /^\|[-|: ]+\|$/) next
    if (!in_table) { 
        print "<table class=\"sortable-table\">"
        print "<thead><tr>"
        n=split($0, a, "|")
        for (i=2; i<n; i++) {
             gsub(/^ +| +$/, "", a[i])
             # Check if we should disable sorting for some columns? No, enable all.
             # Remove markdown bold/code from header text for cleaner display if needed, but browser handles it.
             print "<th onclick=\"sortTable(" i-2 ", this)\">" a[i] "</th>" 
        }
        print "</tr></thead><tbody>"
        in_table=1 
    } else {
        print "<tr>"
        n=split($0, a, "|")
        for (i=2; i<n; i++) {
            gsub(/^ +| +$/, "", a[i])
            print "<td>" a[i] "</td>" 
        }
        print "</tr>"
    }
    next
}
/^\+/ {
    # Detail Row (Deep Dive)
    # Remove "+ " prefix and inject raw HTML into a colspan row
    print "<tr><td colspan=\"9\" style=\"padding:0; border-top:none;\">" substr($0, 3) "</td></tr>"
    next
}
{ 
    if (in_table) { print "</table>"; in_table=0 }
    if (!in_code) print "<p>" $0 "</p>"
    else print $0
}
END { if (in_table) print "</table>"; print "</div>" }
' >> "$HTML_FILE"

# Prepare Chart Data JS
CHART_JS_DATA="const chartData = ["
if [ -f "$TEMP_DIR/charts.dat" ]; then
    while read -r line; do
        IFS='|' read -r node total used lh snap oracle cont logs etcd backup system minio <<< "$line"
        # Calculate Free
        free=$((total - used))
        CHART_JS_DATA="${CHART_JS_DATA}{node:'${node}',lh:${lh},snap:${snap},oracle:${oracle},docker:${cont},logs:${logs},etcd:${etcd},backup:${backup},system:${system},minio:${minio},free:${free}},"
    done < "$TEMP_DIR/charts.dat"
fi
CHART_JS_DATA="${CHART_JS_DATA}];"

cat <<EOF >> "$HTML_FILE"
    </div>
    <div class="footer" style="text-align: center; margin-top: 40px; font-size: 0.9em; color: var(--text-muted); border-top: 1px solid var(--border-color); padding-top: 20px;">
        <p>End of Report. <a href="javascript:window.print()">Save as PDF</a></p>
    </div>

    <script>
        ${CHART_JS_DATA}
EOF

cat <<'EOF' >> "$HTML_FILE"
        const translations = {
            "Storage Inventory Report": "Relatório de Armazenamento",
            "1. Cloud Backup (Google Drive)": "1. Backup em Nuvem (Google Drive)",
            "2. Minio Object Storage (Local)": "2. Armazenamento de Objetos Minio (Local)",
            "3. Node Inventory & Orphans (Potential Cleanup)": "3. Inventário de Nós & Órfãos (Limpeza Potencial)",
            "4. Kubernetes Volumes (PVCs)": "4. Volumes Kubernetes (PVCs)",
            "5. Active Backup Policies": "5. Políticas de Backup Ativas",
            "Type": "Tipo",
            "Name": "Nome",
            "Schedule": "Agendamento",
            "Retention": "Retenção",
            "Target/Group": "Alvo/Grupo",
            "Folder": "Pasta",
            "Real Size": "Tamanho Real",
            "Status & Sync": "Status e Sinc.",
            "Status": "Status",
            "Bucket": "Bucket",
            "Size": "Tamanho",
            "Node": "Nó",
            "Usage": "Uso",
            "System": "Sistema",
            "Generated:": "Gerado em:",
            "Synced": "Sincronizado",
            "✅ Synced": "✅ Sincronizado",
            "Unreachable": "Inacessível",
            "❌ Unreachable": "❌ Inacessível",
            "❌ Error": "❌ Erro",
            "Error": "Erro",
            "Orphan Files": "Arquivos Órfãos",
            "Namespace": "Namespace",
            "Phase": "Fase",
            "Volume": "Volume",
            "Check": "Verificar",
            "Timed out during scan": "Tempo esgotado na verificação",
            "Slow I/O": "E/S Lenta",
            "Review needed": "Revisão necessária",
            "Skipped to speed up report": "Pulado para acelerar relatório",
            "None": "Nenhum",
            "No Data": "Sem Dados",
            "End of Report.": "Fim do Relatório.",
            "Save as PDF": "Salvar como PDF"
        };

        /* Sorting Logic */
        function sortTable(n, header) {
            const table = header.closest("table");
            const tbody = table.querySelector("tbody");
            const rows = Array.from(tbody.rows);
            const isAsc = !header.classList.contains("asc");
            
            // Reset icons
            table.querySelectorAll("th").forEach(th => th.classList.remove("asc", "desc"));
            header.classList.toggle("asc", isAsc);
            header.classList.toggle("desc", !isAsc);
            
            // Helper to parse size (10M, 2G, 500K) -> Bytes
            function parseSize(str) {
                const units = { 'K': 1024, 'M': 1024**2, 'G': 1024**3, 'T': 1024**4, 'P': 1024**5 };
                const match = str.match(/([\d\.]+)\s*([KMGTP])/i);
                if (match) {
                    return parseFloat(match[1]) * (units[match[2].toUpperCase()] || 1);
                }
                if (!isNaN(parseFloat(str))) return parseFloat(str); // Plain number
                return 0;
            }
            
            // Helper to check if string looks like size
            function isSize(str) { return /[\d\.]+\s*[KMGTP]B?$/i.test(str.trim()); }
            
            rows.sort((rA, rB) => {
                let txtA = rA.cells[n].innerText.trim();
                let txtB = rB.cells[n].innerText.trim();
                
                // Extract clean text (remove emoji?)
                txtA = txtA.replace(/[^\w\s\.\-,]/g, "").trim(); 
                txtB = txtB.replace(/[^\w\s\.\-,]/g, "").trim();
                
                // Detect type
                let valA, valB;
                
                if (isSize(txtA) && isSize(txtB)) {
                    valA = parseSize(txtA);
                    valB = parseSize(txtB);
                } else if (!isNaN(Date.parse(txtA)) && !isNaN(Date.parse(txtB)) && txtA.length > 5) {
                    // Date (Jan 18, 2026) -> use Date.parse logic or new Date
                    valA = new Date(txtA).getTime();
                    valB = new Date(txtB).getTime();
                } else if (!isNaN(parseFloat(txtA)) && !isNaN(parseFloat(txtB))) {
                    valA = parseFloat(txtA);
                    valB = parseFloat(txtB);
                } else {
                    valA = txtA.toLowerCase();
                    valB = txtB.toLowerCase();
                }
                
                if (valA < valB) return isAsc ? -1 : 1;
                if (valA > valB) return isAsc ? 1 : -1;
                return 0;
            });
            
            tbody.append(...rows);
        }

        function toggleTheme() {
            const html = document.documentElement;
            const current = html.getAttribute('data-theme');
            const next = current === 'dark' ? 'light' : 'dark';
            html.setAttribute('data-theme', next);
            localStorage.setItem('theme', next);
        }
        
        function openTab(tabName) {
            const contents = document.getElementsByClassName("tab-content");
            for (let content of contents) {
                content.style.display = "none";
                content.classList.remove("active");
            }
            const btns = document.getElementsByClassName("tab-btn");
            for (let btn of btns) {
                btn.classList.remove("active");
            }
            
            const target = document.getElementById(tabName);
            if (target) {
                target.style.display = "block";
                setTimeout(() => target.classList.add("active"), 10);
            }
            
            const btn = document.getElementById("btn-" + tabName);
            if (btn) btn.classList.add("active");
        }

        function toggleLang() {
            const current = localStorage.getItem('lang') || 'en';
            const next = current === 'en' ? 'pt' : 'en';
            localStorage.setItem('lang', next);
            translatePage(next);
            formatDate(next);
        }

        function formatDate(lang) {
            const dateSpan = document.getElementById('report-date');
            if(!dateSpan) return;
            
            const raw = dateSpan.getAttribute('data-timestamp');
            const date = new Date(raw);
            
            let options = { 
                weekday: 'long', 
                year: 'numeric', 
                month: 'long', 
                day: 'numeric', 
                hour: '2-digit', 
                minute: '2-digit',
                timeZoneName: 'short' 
            };
            
            // Adjust locale
            const locale = lang === 'pt' ? 'pt-BR' : 'en-US';
            
            try {
                dateSpan.textContent = new Intl.DateTimeFormat(locale, options).format(date);
            } catch(e) {
                console.error("Date format error", e);
            }
        }

        function translatePage(lang) {
            // Avoid selecting container div which destroys layout
            const elements = document.querySelectorAll('h1, h2, h3, th, td, p, a, .timestamp, .footer');
            
            elements.forEach(el => {
                // Ignore script/style/settings
                if (el.classList.contains('settings-panel') || el.closest('.settings-panel')) return;
                
                // Store original HTML to preserve formatting (b, code, spans)
                if (!el.dataset.originalHtml) el.dataset.originalHtml = el.innerHTML;
                
                const originalHtml = el.dataset.originalHtml;
                // Use textContent for key lookup to match dictionary keys
                const key = el.textContent.trim();
                
                if (lang === 'pt') {
                    // Strategy: Perform replacement on the HTML string
                    let newHtml = originalHtml;
                    
                    // 1. Exact match (Safety first)
                    if (translations[key]) {
                        // If exact match, we can just replace the text but we risk losing tags if key was pure text?
                        // If key was pure text, innerHTML==key.
                        // If element had tags, key != innerHTML.
                        // For exact text matches usually headers/th, simple strings.
                        newHtml = translations[key];
                    } else {
                        // 2. Partial Search & Replace logic
                        // Only replace known phrases to avoid breaking HTML attributes
                        // Sort by length to replace longest phrases first
                        const sortedKeys = Object.keys(translations).sort((a,b) => b.length - a.length);
                        
                        for (const en of sortedKeys) {
                            const pt = translations[en];
                            if (newHtml.includes(en)) {
                                // Simple string replace on HTML. 
                                // Risk: replacing "Size" inside "font-size". 
                                // Mitigation: Our keys are capitalized "Size", attributes are usually lowercase "font-size".
                                newHtml = newHtml.replaceAll(en, pt);
                            }
                        }
                    }
                    el.innerHTML = newHtml;

                } else {
                    // Restore English (Original HTML)
                    el.innerHTML = originalHtml;
                }
            });
        }

        function renderCharts() {
            const container = document.getElementById('charts-area');
            const section = document.getElementById('chart-section');
            if (!container || !chartData.length) return;
            
            section.style.display = 'block';
            container.innerHTML = ''; // Clear
            
            // Helper to format bytes
            function fmtBytes(bytes) {
               if (bytes === 0) return '0 B';
               const k = 1024;
               const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
               // Input is already in KB from script? No, wait. 
               // Script outputs 1K-blocks from `du`.
               // The JS data receives raw numbers.
               // Let's assume input is 1K blocks (KB).
               // Converting to Bytes first for standard logic.
               const b = bytes * 1024;
               const i = Math.floor(Math.log(b) / Math.log(k));
               // Use 1 decimal place as requested
               return parseFloat((b / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
            }

            chartData.forEach(data => {
                const wrapper = document.createElement('div');
                wrapper.className = 'chart-wrapper';
                
                // 1. Chart Area
                const canvasContainer = document.createElement('div');
                canvasContainer.className = 'chart-canvas-container';
                const canvas = document.createElement('canvas');
                canvasContainer.appendChild(canvas);
                
                // 2. Legend Area
                const legend = document.createElement('div');
                legend.className = 'chart-legend';
                
                // Title (Node Name)
                const title = document.createElement('h4');
                title.style.margin = '0 0 10px 0';
                title.textContent = data.node;
                // Prepend title to wrapper instead? No, let's put it top level or inside legend?
                // Layout is flex row. Let's put title above everything?
                // Actually, let's stick to the requested side-by-side. 
                // We'll put the title inside the legend column for compactness or above the wrapper.
                // Let's put it above the wrapper in the existing code... 
                // Wait, previous code put title inside wrapper, then canvas.
                // New layout: Title -> FlexRow(Canvas, Legend)
                
                // Re-structuring wrapper content
                const header = document.createElement('div');
                header.style.width = '100%';
                header.style.textAlign = 'center';
                header.style.marginBottom = '10px';
                header.innerHTML = '<strong>' + data.node + '</strong>';
                wrapper.appendChild(header);
                
                wrapper.appendChild(canvasContainer);
                wrapper.appendChild(legend);
                
                container.appendChild(wrapper);
                
                // Data mapping
                const rawLabels = ['Snap (Cleanable)', 'Oracle Agent', 'Docker (Cleanable)', 'Logs (Cleanable)', 'Longhorn (PVs)', 'System', 'Minio (Data)', 'Etcd', 'Backup', 'Free'];
                const rawValues = [data.snap, data.oracle, data.docker, data.logs, data.lh, data.system, data.minio, data.etcd, data.backup, data.free];
                const rawColors = [
                    '#8e44ad', // Snap
                    '#c0392b', // Oracle
                    '#e74c3c', // Docker
                    '#d35400', // Logs
                    '#3498db', // Longhorn
                    '#7f8c8d', // System
                    '#95a5a6', // Minio
                    '#bdc3c7', // Etcd
                    '#2ecc71', // Backup
                    '#ecf0f1'  // Free
                ];
                
                // Calculate Total for Percentage
                const totalSize = rawValues.reduce((a, b) => a + b, 0);

                // Generate Sorted Data Objects
                let sortedData = rawLabels.map((label, i) => ({
                    label: label,
                    value: rawValues[i],
                    color: rawColors[i],
                    pct: totalSize > 0 ? ((rawValues[i] / totalSize) * 100).toFixed(1) : 0
                })).sort((a, b) => b.value - a.value); // Descending

                // Re-map for Chart (So Chart Slices match Legend Order)
                const sortedLabels = sortedData.map(d => d.label);
                const sortedValues = sortedData.map(d => d.value);
                const sortedColors = sortedData.map(d => d.color);
                
                // Build Legend HTML with Percentages
                let legendHtml = '';
                sortedData.forEach(item => {
                    legendHtml += '<div class="legend-item"><span class="legend-label"><span class="legend-color" style="background:' + item.color + '"></span>' + item.label + '</span><span class="legend-value">' + fmtBytes(item.value) + ' (' + item.pct + '%)</span></div>';
                });
                legend.innerHTML = legendHtml;
                
                // Render Chart with Sorted Data
                new Chart(canvas, {
                    type: 'doughnut',
                    data: {
                        labels: sortedLabels,
                        datasets: [{
                            data: sortedValues,
                            backgroundColor: sortedColors,
                            borderWidth: 1
                        }]
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        plugins: {
                            legend: { display: false }, // Disable default legend, we use custom one
                            tooltip: {
                                callbacks: {
                                    label: function(context) {
                                        // Recalculate pct or use from sortedData? 
                                        // Context index matches sortedData index now.
                                        const item = sortedData[context.dataIndex];
                                        return context.label + ': ' + fmtBytes(context.raw) + ' (' + item.pct + '%)';
                                    }
                                }
                            }
                        }
                    }
                });
            });
        }

        // Init
        (function() {
            const savedTheme = localStorage.getItem('theme') || 'light';
            document.documentElement.setAttribute('data-theme', savedTheme);
            
            const savedLang = localStorage.getItem('lang') || 'en';
            
            setTimeout(() => {
                if (savedLang === 'pt') {
                    translatePage('pt');
                }
                // Always format date to overwrite raw shell timestamp with long format
                formatDate(savedLang);
                
                // Render Charts
                renderCharts();

                // Open default tab
                openTab('tab-storage');
            }, 50);
        })();
    </script>
</body>
</html>
EOF

# ------------------------------------------------------------------------------
# SERVE REPORT & NOTIFY
# ------------------------------------------------------------------------------

# Update 'latest' symlink for consistent serving
REPORT_ROOT="./reports"
LATEST_LINK="$REPORT_ROOT/latest"
if [ -d "$REPORT_ROOT" ]; then
    ln -sfn "$(basename "$OUTPUT_DIR")" "$LATEST_LINK"
fi

# Restart Python HTTP Server (Kill old -> Start new)
if pgrep -f "http.server 8000" >/dev/null; then
    pkill -f "http.server 8000" 2>/dev/null || true
fi

# Start Server in background (Quietly)
nohup python3 -m http.server 8000 --directory "$LATEST_LINK" >/dev/null 2>&1 &
SERVER_PID=$!

echo -e "${GREEN}✨ Reports Generated:${NC}"
echo -e "   📄 Markdown: $MD_FILE"
echo -e "   🌐 HTML (PDF Ready): http://localhost:8000/inventory.html"
echo -e ""
echo -e "${BOLD}Use 'Save as PDF' in your browser to export the HTML report.${NC}"

# Play Sound (Enhanced)
if type alert_sound >/dev/null 2>&1; then
    alert_sound
    # Fallback/Extra for terminal bell
    echo -e "\a"
    if command -v tput >/dev/null; then tput bel; fi
fi
