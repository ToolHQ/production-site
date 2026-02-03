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
ssh -T -o StrictHostKeyChecking=no "$MASTER_NODE" "kubectl top nodes --no-headers > /tmp/nodes_usage.txt && kubectl get nodes -o json > /tmp/nodes_capacity.json && kubectl get pods -A -o json > /tmp/pods_resources.json && kubectl top pods -A --no-headers > /tmp/pods_usage.txt"
scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/nodes_usage.txt" "$TEMP_DIR/nodes_usage.txt"
scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/nodes_capacity.json" "$TEMP_DIR/nodes_capacity.json"
scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/pods_resources.json" "$TEMP_DIR/pods_resources.json"
scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/pods_usage.txt" "$TEMP_DIR/pods_usage.txt"

# Fetch Node Statistics (for ephemeral storage usage)
echo -e "   [master] Fetching Node Statistics..."
for node in "${CLUSTER_NODES[@]}"; do
    k8s_node_name="${node#oci-}"
    ssh -T -o StrictHostKeyChecking=no "$MASTER_NODE" "kubectl get --raw /api/v1/nodes/$k8s_node_name/proxy/stats/summary > /tmp/node_stats_$k8s_node_name.json" 2>/dev/null &
done
wait
for node in "${CLUSTER_NODES[@]}"; do
    k8s_node_name="${node#oci-}"
    scp -q -o StrictHostKeyChecking=no "$MASTER_NODE:/tmp/node_stats_$k8s_node_name.json" "$TEMP_DIR/node_stats_$k8s_node_name.json"
done

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
    echo "--- SYSTEM_TOP ---"
    du -xSh / --exclude='/var/lib/docker' --exclude='/var/lib/containerd' --exclude='/var/lib/longhorn' --exclude='/var/lib/etcd' --exclude='/var/backup' --exclude='/data' --exclude='/proc' --exclude='/sys' 2>/dev/null | sort -rh | head -n 10 | awk '{print $1, substr($2, length($2)-50)}' || echo "Error scanning system"

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
        \( -path "/proc" -o -path "/sys" -o -path "/run" -o -path "/var/lib/docker" -o -path "/var/lib/kubelet" -o -path "/var/lib/containerd" -o -path "/var/lib/longhorn" -o -path "/data/minio/k8s-backups" \) -prune \
        -o -type f \
        \( -name "*.tar.gz" -o -name "*.zip" -o -name "*.sql" -o -name "*.db" -o -name "*.bak" -o -name "*.tar" \) \
        -size +50M \
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
# Deep dive: backupstore/volumes breakdown (GDrive) - Parallelized
ssh -T -o StrictHostKeyChecking=no oci-k8s-master 'bash -s' <<'EndSSH' > "$TEMP_DIR/gdrive_backupstore_volumes.txt" 2>&1 &
    fetch_size() {
        vol="$1"
        size_json=$(sudo rclone size "gdrive:k8s-backups/backupstore/volumes/$vol" --config /root/.config/rclone/rclone.conf --json 2>/dev/null)
        bytes=$(echo "$size_json" | jq .bytes 2>/dev/null | numfmt --to=iec 2>/dev/null)
        count=$(echo "$size_json" | jq .count 2>/dev/null)
        echo "$vol|$bytes|$count"
    }
    export -f fetch_size
    # List volumes and run in parallel (max 5 jobs)
    sudo rclone lsd gdrive:k8s-backups/backupstore/volumes --config /root/.config/rclone/rclone.conf 2>/dev/null | awk '{print $5}' | xargs -P 5 -I {} bash -c 'fetch_size "{}"'
EndSSH
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

# Extract Longhorn metadata from GDrive backupstore - Parallelized
ssh -T -o StrictHostKeyChecking=no oci-k8s-master 'bash -s' <<'GDRIVE_METADATA_SCRIPT' > "$TEMP_DIR/gdrive_volume_metadata.txt" 2>&1 &
    fetch_meta() {
        vol="$1"
        # Download volume.cfg/xl.meta from GDrive
        pvc_path=$(sudo rclone lsf "gdrive:k8s-backups/backupstore/volumes/$vol" --dirs-only --config /root/.config/rclone/rclone.conf 2>/dev/null | head -n 1 | sed 's|/$||')
        if [ -n "$pvc_path" ]; then
            meta=$(sudo rclone cat "gdrive:k8s-backups/backupstore/volumes/$vol/$pvc_path/volume.cfg/xl.meta" --config /root/.config/rclone/rclone.conf 2>/dev/null | tr -d '\000' | grep -oP '\{.*\}' | head -n 1)
            if [ -n "$meta" ]; then
                pvc_name=$(echo "$meta" | jq -r '.Labels.KubernetesStatus.pvcName' 2>/dev/null)
                namespace=$(echo "$meta" | jq -r '.Labels.KubernetesStatus.namespace' 2>/dev/null)
                created=$(echo "$meta" | jq -r '.CreatedTime' 2>/dev/null)
                last_backup=$(echo "$meta" | jq -r '.LastBackupAt' 2>/dev/null)
                size=$(echo "$meta" | jq -r '.Size' 2>/dev/null | numfmt --to=iec 2>/dev/null)
                echo "$vol|$pvc_name|$namespace|$created|$last_backup|$size"
            fi
        fi
    }
    export -f fetch_meta
    sudo rclone lsd gdrive:k8s-backups/backupstore/volumes --config /root/.config/rclone/rclone.conf 2>/dev/null | awk '{print $5}' | xargs -P 8 -I {} bash -c 'fetch_meta "{}"'
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
    echo "## 6. Compute Resources (CPU/RAM/Disk)"
    echo "| Node | CPU Usage | CPU Req/Lim | Mem Usage | Mem Req/Lim | Eph. Disk | Status |"
    echo "|---|---|---|---|---|---|---|"
    
    # Helper to convert to millicores/Mi
    to_milli() {
        val=$1
        if [[ -z "$val" || "$val" == "null" || "$val" == "0" ]]; then echo "0"; return; fi
        if [[ "$val" == *"m" ]]; then echo "${val%m}"; 
        elif [[ "$val" =~ ^[0-9]+$ ]]; then echo "$((val * 1000))";
        else echo "0"; fi
    }
    
    to_mi() {
        val=$1
        if [[ -z "$val" || "$val" == "null" || "$val" == "0" ]]; then echo "0"; return; fi
        if [[ "$val" == *"Ki" ]]; then echo $(( ${val%Ki} / 1024 ));
        elif [[ "$val" == *"Mi" ]]; then echo "${val%Mi}"; 
        elif [[ "$val" == *"Gi" ]]; then echo $(( ${val%Gi} * 1024 ));
        elif [[ "$val" =~ ^[0-9]+$ ]]; then echo $(( val / 1024 / 1024 ));
        else echo "0"; fi
    }

    format_limit() {
        val=$1; unit=$2
        if [[ "$val" == "0" ]]; then echo "∞"; else echo "${val}${unit}"; fi
    }

    if [ -f "$TEMP_DIR/nodes_usage.txt" ] && [ -f "$TEMP_DIR/pods_resources.json" ]; then
        for node in "${CLUSTER_NODES[@]}"; do
            # Usage (from top) - Strip oci- prefix to match k8s node name
            k8s_node_name="${node#oci-}"
            read -r _ u_cpu u_cpu_pct u_mem u_mem_pct <<< $(grep "$k8s_node_name" "$TEMP_DIR/nodes_usage.txt" || echo "0 0m 0% 0Mi 0%")
            
            # Node Capacity (Allocatable)
            cap_cpu=$(jq -r --arg n "$k8s_node_name" '.items[] | select(.metadata.name==$n) | .status.allocatable.cpu' "$TEMP_DIR/nodes_capacity.json")
            cap_mem=$(jq -r --arg n "$k8s_node_name" '.items[] | select(.metadata.name==$n) | .status.allocatable.memory' "$TEMP_DIR/nodes_capacity.json")
            cap_cpu_m=$(to_milli "$cap_cpu")
            cap_mem_mi=$(to_mi "$cap_mem")

            # Requests/Limits (Sum from non-terminated Pods)
            # Use k8s_node_name for pod aggregation and filter out ended pods
            cpu_stats=$(jq -r --arg n "$k8s_node_name" "[.items[] | select(.spec.nodeName==\$n and .status.phase!=\"Succeeded\" and .status.phase!=\"Failed\") | .spec.containers[]?.resources.requests.cpu // \"0\"] | map(if . == \"0\" then 0 elif endswith(\"m\") then (sub(\"m\"; \"\") | tonumber) else (tonumber? * 1000 // 0) end) | add // 0" "$TEMP_DIR/pods_resources.json")
            cpu_lims=$(jq -r --arg n "$k8s_node_name" "[.items[] | select(.spec.nodeName==\$n and .status.phase!=\"Succeeded\" and .status.phase!=\"Failed\") | .spec.containers[]?.resources.limits.cpu // \"0\"] | map(if . == \"0\" then 0 elif endswith(\"m\") then (sub(\"m\"; \"\") | tonumber) else (tonumber? * 1000 // 0) end) | add // 0" "$TEMP_DIR/pods_resources.json")
            
            mem_stats=$(jq -r --arg n "$k8s_node_name" "[.items[] | select(.spec.nodeName==\$n and .status.phase!=\"Succeeded\" and .status.phase!=\"Failed\") | .spec.containers[]?.resources.requests.memory // \"0\"] | map(if . == \"0\" then 0 elif endswith(\"Gi\") then (sub(\"Gi\"; \"\") | tonumber * 1024) elif endswith(\"Mi\") then (sub(\"Mi\"; \"\") | tonumber) elif endswith(\"Ki\") then (sub(\"Ki\"; \"\") | tonumber / 1024) else 0 end) | add // 0" "$TEMP_DIR/pods_resources.json")
            mem_lims=$(jq -r --arg n "$k8s_node_name" "[.items[] | select(.spec.nodeName==\$n and .status.phase!=\"Succeeded\" and .status.phase!=\"Failed\") | .spec.containers[]?.resources.limits.memory // \"0\"] | map(if . == \"0\" then 0 elif endswith(\"Gi\") then (sub(\"Gi\"; \"\") | tonumber * 1024) elif endswith(\"Mi\") then (sub(\"Mi\"; \"\") | tonumber) elif endswith(\"Ki\") then (sub(\"Ki\"; \"\") | tonumber / 1024) else 0 end) | add // 0" "$TEMP_DIR/pods_resources.json")

            # Format (CPU in m, Mem in Mi)
            cpu_req="${cpu_stats}m"
            cpu_lim=$(format_limit "$cpu_lims" "m")
            mem_req="${mem_stats}Mi"
            mem_lim=$(format_limit "$mem_lims" "Mi")
            
            # Status Icon (Based on CPU/Mem %)
            c_p=${u_cpu_pct%\%}
            m_p=${u_mem_pct%\%}
            icon="🟢"
            if [ "$c_p" -gt 85 ] || [ "$m_p" -gt 85 ]; then icon="🔴"; elif [ "$c_p" -gt 70 ] || [ "$m_p" -gt 70 ]; then icon="🟡"; fi

            # Ephemeral Storage from stats summary (Fallback to .node.fs if specialized key missing)
            if [ -f "$TEMP_DIR/node_stats_$k8s_node_name.json" ]; then
                eph_used_b=$(jq -r '.node["ephemeral-storage"].usedBytes // .node.fs.usedBytes // 0' "$TEMP_DIR/node_stats_$k8s_node_name.json")
                eph_total_b=$(jq -r '.node["ephemeral-storage"].capacityBytes // .node.fs.capacityBytes // 0' "$TEMP_DIR/node_stats_$k8s_node_name.json")
                eph_used_h=$(numfmt --to=iec "$eph_used_b" 2>/dev/null || echo "0B")
                eph_total_h=$(numfmt --to=iec "$eph_total_b" 2>/dev/null || echo "0B")
                eph_pct="0"
                if [ "$eph_total_b" -gt 0 ]; then eph_pct=$(( (eph_used_b * 100) / eph_total_b )); fi
                eph_label="$eph_used_h ($eph_pct% / $eph_total_h)"
            else
                eph_label="-"
            fi

            echo "| **$node** | $u_cpu ($u_cpu_pct / ${cap_cpu_m}m) | R: $cpu_req / L: $cpu_lim | $u_mem ($u_mem_pct / ${cap_mem_mi}Mi) | R: $mem_req / L: $mem_lim | $eph_label | $icon |"
        done

        # Detailed Pod Breakdown (Enhanced with Status & Alarms)
        echo ""
        echo "## 7. Detailed Pod Resource Breakdown"
        echo "| Namespace | Pod Name | CPU (Usage/Req/Lim) | CPU Eff | Mem (Usage/Req/Lim) | Mem Eff | Eph. Disk (Usage/Req/Lim) | Disk Eff | Total Eff | Status | Node |"
        echo "|---|---|---|---|---|---|---|---|---|---|---|"
        
        # Build pod usage map
        declare -A pod_cpu_usage
        declare -A pod_mem_usage
        declare -A pod_eph_usage
        while read -r ns name cpu mem; do
            pod_cpu_usage["$ns/$name"]="$cpu"
            pod_mem_usage["$ns/$name"]="$mem"
        done < "$TEMP_DIR/pods_usage.txt"

        # Extract Ephemeral Usage from node stats
        for node in "${CLUSTER_NODES[@]}"; do
            k8s_node_name="${node#oci-}"
            if [ -f "$TEMP_DIR/node_stats_$k8s_node_name.json" ]; then
                while read -r cp_key cp_used; do
                    pod_eph_usage["$cp_key"]="$cp_used"
                done < <(jq -r '.pods[] | "\(.podRef.namespace)/\(.podRef.name) \(.["ephemeral-storage"].usedBytes // 0)"' "$TEMP_DIR/node_stats_$k8s_node_name.json")
            fi
        done

        # Include ALL pods in Section 7 breakdown, but flag their status
        jq -r '.items[] | 
               [ .metadata.namespace, 
                 .metadata.name, 
                 .spec.nodeName,
                 ([.spec.containers[]?.resources.requests.cpu // "0"] | map(if endswith("m") then (sub("m";"")|tonumber) else (tonumber? // 0) * 1000 end) | add // 0),
                 ([.spec.containers[]?.resources.requests.memory // "0"] | map(if endswith("Gi") then (sub("Gi";"")|tonumber*1024) elif endswith("Mi") then (sub("Mi";"")|tonumber) elif endswith("Ki") then (sub("Ki";"")|tonumber/1024) else (tonumber? // 0) / 1024 / 1024 end) | add // 0),
                 ([.spec.containers[]?.resources.limits.cpu // "0"] | map(if endswith("m") then (sub("m";"")|tonumber) else (tonumber? // 0) * 1000 end) | add // 0),
                 ([.spec.containers[]?.resources.limits.memory // "0"] | map(if endswith("Gi") then (sub("Gi";"")|tonumber*1024) elif endswith("Mi") then (sub("Mi";"")|tonumber) elif endswith("Ki") then (sub("Ki";"")|tonumber/1024) else (tonumber? // 0) / 1024 / 1024 end) | add // 0),
                 ([.spec.containers[]?.resources.requests["ephemeral-storage"] // "0"] | map(if endswith("Gi") then (sub("Gi";"")|tonumber*1024) elif endswith("Mi") then (sub("Mi";"")|tonumber) elif endswith("Ki") then (sub("Ki";"")|tonumber/1024) else (tonumber? // 0) / 1024 / 1024 end) | add // 0),
                 ([.spec.containers[]?.resources.limits["ephemeral-storage"] // "0"] | map(if endswith("Gi") then (sub("Gi";"")|tonumber*1024) elif endswith("Mi") then (sub("Mi";"")|tonumber) elif endswith("Ki") then (sub("Ki";"")|tonumber/1024) else (tonumber? // 0) / 1024 / 1024 end) | add // 0),
                 .status.phase
               ] | join("|")' "$TEMP_DIR/pods_resources.json" | \
        while IFS='|' read -r ns name p_node c_req_m m_req_mi c_lim_m m_lim_mi e_req_mi e_lim_mi status; do
            u_cpu=${pod_cpu_usage["$ns/$name"]:-"0m"}
            u_mem=${pod_mem_usage["$ns/$name"]:-"0Mi"}
            u_eph_b=${pod_eph_usage["$ns/$name"]:-"0"}
            u_eph_h=$(numfmt --to=iec "$u_eph_b" 2>/dev/null || echo "0B")
            
            u_cpu_m=$(to_milli "$u_cpu")
            u_mem_mi=$(to_mi "$u_mem")

            # Alarms for missing config
            c_alarm=""; if [ "$c_req_m" -eq 0 ] || [ "$c_lim_m" -eq 0 ]; then c_alarm="🚩 "; fi
            m_alarm=""; if [ "$m_req_mi" -eq 0 ] || [ "$m_lim_mi" -eq 0 ]; then m_alarm="🚩 "; fi
            e_alarm=""; if [ "$e_req_mi" -eq 0 ] || [ "$e_lim_mi" -eq 0 ]; then e_alarm="🚩 "; fi

            # Helper for displaying percentage
            fmt_pct() {
                local u=$1
                local r=$2
                if [ "$r" -eq 0 ]; then echo "-"; return; fi
                local p=$(( (u * 100) / r ))
                if [ "$p" -eq 0 ] && [ "$u" -gt 0 ]; then echo "<1%"; else echo "${p}%"; fi
            }

            # CPU Efficiency
            eff_cpu=$(fmt_pct "$u_cpu_m" "$c_req_m")
            c_icon="🟢"
            # EFFICIENCY CHECK:
            # 1. If Usage > 90% -> Warning (⚠️)
            # 2. If Request <= 50m -> Accept Low Efficiency/Idle (🟢) per user rule (Min alloc = 50m)
            # 3. If Efficiency < 5% -> Waste (📉)
            if [[ "$eff_cpu" != "-" ]]; then
                val=${eff_cpu%\%}; val=${val#<}
                
                if [ "$val" -gt 90 ]; then
                     c_icon="⚠️"
                elif [ "$c_req_m" -le 50 ]; then
                     c_icon="🟢" # Floor Exemption: 50m
                elif [ "$val" -lt 5 ]; then 
                     c_icon="📉"
                else
                     c_icon="🟢"
                fi
            fi
            if [ -n "$c_alarm" ]; then c_icon="🚩"; fi

            # Mem Efficiency
            eff_mem=$(fmt_pct "$u_mem_mi" "$m_req_mi")
            m_icon="🟢"
            # Only flag low efficiency if request is significant (> 256Mi)
            if [[ "$eff_mem" != "-" ]]; then
                val=${eff_mem%\%}; val=${val#<}
                if [ "$val" -lt 10 ]; then 
                     # Floor Exemption for Memory (<= 64Mi)
                     if [ "$m_req_mi" -le 64 ]; then m_icon="🟢"; else m_icon="📉"; fi
                elif [ "$val" -gt 90 ]; then m_icon="⚠️"; fi
            fi
            if [ -n "$m_alarm" ]; then m_icon="🚩"; fi

            # Eph Disk Efficiency (Usage/Request)
            # Use KB for better precision on small usage (avoid 0% when used > 0)
            u_eph_kb=$(( u_eph_b / 1024 ))
            e_req_kb=$(( e_req_mi * 1024 ))
            
            eff_eph="-"
            e_icon="⚪" # Default to Neutral/Idle
            
            if [ "$e_req_kb" -gt 0 ]; then
                pct=$(( (u_eph_kb * 100) / e_req_kb ))
                if [ "$pct" -eq 0 ] && [ "$u_eph_kb" -gt 0 ]; then
                    eff_eph="<1%"
                    e_icon="🟢" # Tiny usage is fine/good
                elif [ "$pct" -eq 0 ]; then
                     eff_eph="0%"
                     e_icon="⚪" # Truly empty/idle
                else
                    eff_eph="${pct}%"
                    e_icon="🟢" # Normal usage
                    if [ "$pct" -gt 80 ]; then e_icon="⚠️"; fi # Saturation warning
                fi
            fi
            
            if [ -n "$e_alarm" ]; then e_icon="🚩"; eff_eph="-"; fi
            
            # Total Efficiency (Avg of CPU & Mem only - Disk is excluded)
            # We want to know how well we sized the COMPUTE.
            total_sum=0
            total_count=0
            
            if [[ "$eff_cpu" != "-" ]]; then 
                val=${eff_cpu%\%}; val=${val#<}
                total_sum=$((total_sum + val))
                total_count=$((total_count+1))
            fi
            if [[ "$eff_mem" != "-" ]]; then 
                val=${eff_mem%\%}; val=${val#<}
                total_sum=$((total_sum + val))
                total_count=$((total_count+1))
            fi
            
            eff_total="-"
            t_icon="⚪"
            if [ "$total_count" -gt 0 ]; then
                raw_total=$(( total_sum / total_count ))
                eff_total="${raw_total}%"
                # Total efficiency low warning only if significant waste
                if [ "$raw_total" -lt 10 ]; then t_icon="📉"; elif [ "$raw_total" -gt 85 ]; then t_icon="⚠️"; else t_icon="🟢"; fi
            fi

            # Format Limits for table
            c_lim_label=$(format_limit "$c_lim_m" "m")
            m_lim_label=$(format_limit "$m_lim_mi" "Mi")
            e_lim_label=$(format_limit "$e_lim_mi" "Mi")
            
            # Status badge logic
            st_color="gray"; if [ "$status" == "Running" ]; then st_color="green"; elif [ "$status" == "Failed" ]; then st_color="red"; fi
            st_label="<span style=\"color:$st_color\">$status</span>"

            echo "| $ns | \`$name\` | ${c_alarm}${u_cpu} / ${c_req_m}m / $c_lim_label | $c_icon $eff_cpu | ${m_alarm}${u_mem} / ${m_req_mi}Mi / $m_lim_label | $m_icon $eff_mem | ${e_alarm}${u_eph_h} / ${e_req_mi}Mi / $e_lim_label | $e_icon $eff_eph | $t_icon $eff_total | $st_label | $p_node |"
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

        body { 
            font-family: 'Inter', -apple-system, sans-serif; 
            line-height: 1.5; 
            background: var(--bg-body); 
            color: var(--text-main); 
            margin: 0; 
            padding: 0; 
            display: flex;
            justify-content: center;
        }
        .container { 
            max-width: 1400px; 
            width: 100%;
            margin: 40px 20px;
            background: var(--bg-container); 
            padding: 40px 60px; 
            border-radius: 16px; 
            box-shadow: 0 10px 40px rgba(0,0,0,0.12); 
            border: 1px solid var(--border-color);
            position: relative;
        }
        
        /* Header & Navigation Area */
        .report-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 30px;
            border-bottom: 2px solid var(--header-border);
            padding-bottom: 20px;
        }
        .header-left h1 { margin: 0 0 10px 0; border: none; padding: 0; }
        .header-right { display: flex; flex-direction: column; align-items: flex-end; gap: 15px; }

        .settings-panel { display: flex; gap: 12px; }
        .btn-toggle { background: var(--bg-body); border: 1px solid var(--border-color); padding: 8px 14px; border-radius: 20px; cursor: pointer; color: var(--text-main); font-size: 1em; transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1); box-shadow: 0 2px 5px rgba(0,0,0,0.05); }
        .btn-toggle:hover { background: var(--th-bg); transform: translateY(-2px); box-shadow: 0 4px 10px rgba(0,0,0,0.1); }

        /* Tabs Redesign */
        .tabs { display: flex; gap: 15px; margin-bottom: 0; border: none; padding: 0; }
        .tab-btn { background: var(--bg-body); border: 1px solid var(--border-color); padding: 12px 24px; font-size: 1.05em; cursor: pointer; color: var(--text-muted); border-radius: 10px; transition: all 0.3s; font-weight: 600; }
        .tab-btn:hover { background: var(--th-bg); color: var(--text-main); }
        .tab-btn.active { background: var(--header-border); color: white; border-color: var(--header-border); box-shadow: 0 4px 12px rgba(41, 128, 185, 0.3); }

        /* Toolbar Area (Search + Extra Info) */
        .toolbar {
            display: grid;
            grid-template-columns: 1fr auto;
            gap: 20px;
            align-items: center;
            background: var(--bg-body);
            padding: 25px;
            border-radius: 12px;
            margin-bottom: 40px;
            border: 1px solid var(--border-color);
        }
        .search-box { position: relative; width: 100%; max-width: 500px; }
        .search-box input { width: 100%; padding: 14px 20px 14px 50px; border: 1.5px solid var(--border-color); border-radius: 10px; background: var(--bg-container); color: var(--text-main); font-size: 1.05em; outline: none; transition: all 0.3s; }
        .search-box input:focus { border-color: var(--header-border); box-shadow: 0 0 0 4px rgba(41, 128, 185, 0.15); }
        .search-icon { position: absolute; left: 18px; top: 50%; transform: translateY(-50%); color: var(--text-muted); font-size: 1.25em; pointer-events: none; }
        .match-info { font-size: 0.95em; color: var(--text-muted); font-weight: 500; text-align: right; }

        h2 { color: var(--header-border); margin: 50px 0 20px 0; border-bottom: 1px solid var(--border-color); padding-bottom: 12px; font-size: 1.6em; }
        h3 { color: var(--text-muted); margin-top: 35px; font-size: 1.3em; }

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

        /* Search & Filter UI - Cleanup old classes */
        .filter-select { font-size: 0.8em; padding: 6px; border-radius: 6px; border: 1px solid var(--border-color); background: var(--bg-body); color: var(--text-main); margin-top: 10px; width: 100%; display: none; font-weight: normal; }
        th:hover .filter-select { display: block; }

        /* Legend Card Style */
        .legend-footer { margin-top: 60px; padding: 30px; background: var(--bg-body); border-radius: 12px; border: 1px solid var(--border-color); box-shadow: inset 0 2px 10px rgba(0,0,0,0.05); }
        .legend-footer h3 { margin-top: 0; color: var(--header-border); font-size: 1.2em; border-bottom: 1px solid var(--border-color); padding-bottom: 15px; margin-bottom: 25px; display: flex; align-items: center; gap: 10px; }
        .legend-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 30px; }
        .legend-group-title { font-weight: 700; font-size: 0.85em; margin-bottom: 15px; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.05em; }
        .legend-item-row { display: flex; align-items: center; gap: 12px; margin-bottom: 10px; font-size: 0.9em; line-height: 1.4; }
        .icon-box { font-size: 1.3em; min-width: 30px; text-align: center; }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="container">
        <header class="report-header">
            <div class="header-left">
                <h1 data-i18n="Storage Inventory Report">Storage Inventory Report</h1>
                <div class="timestamp">
                    <span data-i18n="Generated:">Generated:</span> 
                    <span id="report-date" data-timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)">$(date -u)</span>
                </div>
            </div>
            <div class="header-right">
                <div class="settings-panel">
                     <button class="btn-toggle" onclick="toggleLang()" title="Switch Language">🇧🇷 / 🇺🇸</button>
                     <button class="btn-toggle" onclick="toggleTheme()" title="Toggle Dark Mode">🌙 / ☀️</button>
                </div>
                <nav class="tabs">
                    <button id="btn-tab-storage" class="tab-btn active" onclick="openTab('tab-storage')" data-i18n="Storage">Storage</button>
                    <button id="btn-tab-compute" class="tab-btn" onclick="openTab('tab-compute')" data-i18n="Compute (CPU/RAM/Disk)">Compute (CPU/RAM/Disk)</button>
                </nav>
            </div>
        </header>

        <section class="toolbar">
            <div class="search-box">
                <input type="text" id="global-search" onkeyup="globalSearch()" placeholder="Search in all tables..." data-i18n-placeholder="Search in all tables...">
                <span class="search-icon">🔍</span>
            </div>
            <div id="match-count" class="match-info" data-i18n="Showing all rows">Showing all rows</div>
        </section>
EOF

# Convert MD to basic HTML (Primitive parser for tables and headers)
sed -E 's/^# (.*)/<h1>\1<\/h1>/' "$MD_FILE" | \
sed -E 's/^## (.*)/<h2>\1<\/h2>/' | \
sed -E 's/^### (.*)/<h3>\1<\/h3>/' | \
sed -E 's/\*\*([^*]+)\*\*/<b>\1<\/b>/g' | \
sed -E 's/`([^`]+)`/<code>\1<\/code>/g' | \
sed -E 's/🟢/<span title="Normal Status">🟢<\/span>/g' | \
sed -E 's/🟡/<span title="Warning: High Usage">🟡<\/span>/g' | \
sed -E 's/🔴/<span title="Critical: Danger">🔴<\/span>/g' | \
sed -E 's/🚩/<span title="Alarm: Missing Resource Config (Requests\/Limits)">🚩<\/span>/g' | \
sed -E 's/📉/<span title="Inefficient: Under-utilized resources">📉<\/span>/g' | \
sed -E 's/⚠️/<span title="Pressure: Usage close to limits">⚠️<\/span>/g' | \
sed -E 's/✅/<span title="Synced & Healthy">✅<\/span>/g' | \
sed -E 's/❌/<span title="Error or Connection Issues">❌<\/span>/g' | \
awk '
BEGIN { 
    print "<div id=\"tab-storage\" class=\"tab-content active\">";
    print "<div id=\"chart-section\" style=\"margin-top: 30px; display:none;\">";
    print "<h2><span data-i18n=\"Storage Distribution (Visual)\">📊 Storage Distribution (Visual)</span></h2>";
    print "<div id=\"charts-area\" class=\"chart-grid\"></div>";
    print "</div>";
    in_table=0; in_code=0 
}
# Helper to extract sort value
function get_sort_val(str) {
    # 0. Clean HTML tags (e.g. spans with titles)
    # Use global sub to match <...>
    clean_html = str
    gsub(/<[^>]+>/, "", clean_html)

    # 1. Handle Multi-value (Usage / Req / Lim) - Take first part only!
    split(clean_html, parts, /[\/()]/)
    clean = parts[1]
    
    # 2. Handle Infinity
    if (clean ~ /∞/) return "Infinity"
    if (clean ~ /^[ \t-]*$/) return "-1"
    
    # 3. Extract number and unit
    # Remove markdown **, _
    gsub(/[*_`]/, "", clean)
    # Remove leading icons/spaces until a number appears
    sub(/^[^0-9-]*/, "", clean)
    
    # Match number
    match(clean, /^-?[0-9]+([.][0-9]+)?/)
    if (RSTART == 0) return "-1"
    val = substr(clean, RSTART, RLENGTH)
    
    # Get Unit (rest of string after number)
    rest = substr(clean, RSTART + RLENGTH)
    # Trim leading space from unit
    sub(/^[ \t]+/, "", rest)
    # Extract just the unit part (letters/%/trailing stuff)
    match(rest, /^[a-zA-Z%]+/)
    unit = substr(rest, RSTART, RLENGTH)
    
    # Scale
    num = val + 0
    if (unit == "m") return num * 0.001
    
    u = tolower(unit)
    if (index(u, "k") == 1) return num * 1024
    if (index(u, "m") == 1) return num * 1048576
    if (index(u, "g") == 1) return num * 1073741824
    if (index(u, "t") == 1) return num * 1099511627776
    if (index(u, "p") == 1) return num * 1125899906842624
    
    return num
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
             print "<th><div class=\"filter-header\">"
             print "<span data-i18n=\"" a[i] "\">" a[i] "</span>"
             print "</div>"
             print "<select class=\"filter-select\" onchange=\"filterTable(this, " i-2 ")\" onclick=\"event.stopPropagation()\"><option value=\"\" data-i18n=\"All\">All</option></select></th>" 
        }
        print "</tr></thead><tbody>"
        in_table=1 
    } else {
        print "<tr>"
        n=split($0, a, "|")
        for (i=2; i<n; i++) {
            gsub(/^ +| +$/, "", a[i])
            sort_val = get_sort_val(a[i])
            print "<td data-sort-value=\"" sort_val "\">" a[i] "</td>" 
        }
        print "</tr>"
    }
    next
}
/^\+/ {
    # Detail Row (Deep Dive)
    # Remove "+ " prefix and inject raw HTML into a colspan row
    print "<tr class=\"detail-row\"><td colspan=\"9\" style=\"padding:0; border-top:none;\">" substr($0, 3) "</td></tr>"
    next
}
{ 
    if (in_table) { print "</table>"; in_table=0 }
    if (!in_code) {
        if ($0 ~ /^<h[1-3]/) print $0
        else {
             # Clean any potential stray legend leftovers if moving them
             if ($0 !~ /legend-footer|legend-grid/) print "<p>" $0 "</p>"
        }
    }
    else print $0
}
END { 
    if (in_table) print "</table>";
    print "    </div> <!-- End Container Content -->"
    print "    <div class=\"legend-footer\" data-i18n-no-translate>"
    print "        <h3><span data-i18n=\"📖 Report Legend & Icon Meanings\">📖 Report Legend & Icon Meanings</span></h3>"
    print "        <div class=\"legend-grid\">"
    print "            <div class=\"legend-column\">"
    print "                <div class=\"legend-group-title\" data-i18n=\"Node & Storage Health\">Node & Storage Health</div>"
    print "                <div class=\"legend-item-row\"><span class=\"icon-box\">🟢</span> <span data-i18n=\"Normal Status\">Normal Status</span></div>"
    print "                <div class=\"legend-item-row\"><span class=\"icon-box\">🟡</span> <span data-i18n=\"Warning Usage\">Warning: High Usage (>70%)</span></div>"
    print "                <div class=\"legend-item-row\"><span class=\"icon-box\">🔴</span> <span data-i18n=\"Critical Usage\">Critical: Danger (>85%)</span></div>"
    print "            </div>"
    print "            <div class=\"legend-column\">"
    print "                <div class=\"legend-group-title\" data-i18n=\"Pod Alarms (Section 7)\">Pod Alarms (Section 7)</div>"
    print "                <div class=\"legend-item-row\"><span class=\"icon-box\">🚩</span> <span data-i18n=\"Missing Config\">Missing Requests/Limits</span></div>"
    print "                <div class=\"legend-item-row\"><span class=\"icon-box\">📉</span> <span data-i18n=\"Underutilized\">Under-utilized (<5% CPU, <10% RAM) [Above Floor]</span></div>"
    print "                <div class=\"legend-item-row\"><span class=\"icon-box\">🟢</span> <span data-i18n=\"Normal Status\">Normal / Floor (CPU≤50m, RAM≤64Mi)</span></div>"
    print "                <div class=\"legend-item-row\"><span class=\"icon-box\">⚠️</span> <span data-i18n=\"Close to Limit\">Close to Limit (>90% of Req)</span></div>"
    print "            </div>"
    print "            <div class=\"legend-column\">"
    print "                <div class=\"legend-group-title\" data-i18n=\"Cloud & Connectivity\">Cloud & Connectivity</div>"
    print "                <div class=\"legend-item-row\"><span class=\"icon-box\">✅</span> <span data-i18n=\"Synced Healthy\">Synced & Healthy</span></div>"
    print "                <div class=\"legend-item-row\"><span class=\"icon-box\">❌</span> <span data-i18n=\"Connection Error\">Connection Error / Node Down</span></div>"
    print "                <div class=\"legend-item-row\"><span class=\"icon-box\">📜</span> <span data-i18n=\"Snapshots View\">Click to view local snapshots</span></div>"
    print "            </div>"
    print "        </div>"
    print "    </div>"
    print "    <div class=\"footer\" style=\"text-align: center; margin-top: 60px; font-size: 0.95em; color: var(--text-muted); border-top: 1px solid var(--border-color); padding-top: 30px;\">"
    print "        <p><span data-i18n=\"End of Report.\">End of Report.</span> <a href=\"javascript:window.print()\" data-i18n=\"Save as PDF\">Save as PDF</a></p>"
    print "    </div>"
    print "</div> <!-- End main container -->" 
}
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
            "6. Compute Resources (CPU/RAM/Disk)": "6. Recursos Computacionais (CPU/RAM/Disco)",
            "7. Detailed Pod Resource Breakdown": "7. Detalhamento de Recursos dos Pods",
            "📊 Storage Distribution (Visual)": "📊 Distribuição de Armazenamento (Visual)",
            "Storage Distribution (Visual)": "Distribuição de Armazenamento (Visual)",
            "Storage": "Armazenamento",
            "Compute (CPU/RAM/Disk)": "Computação (CPU/RAM/Disco)",
            "Search in all tables...": "Buscar em todas as tabelas...",
            "Showing all rows": "Exibindo todas as linhas",
            "Matched": "Encontrado",
            "of": "de",
            "rows": "linhas",
            "All": "Tudo",
            "Type": "Tipo",
            "Name": "Nome",
            "Namespace": "Namespace",
            "Phase": "Fase",
            "Status": "Status",
            "Volume": "Volume",
            "Folder": "Pasta",
            "Real Size": "Tamanho Real",
            "Size": "Tamanho",
            "Usage": "Uso",
            "System": "Sistema",
            "Node": "Nó",
            "Schedule": "Agendamento",
            "Retention": "Retenção",
            "Target/Group": "Alvo/Grupo",
            "Generated:": "Gerado em:",
            "📖 Report Legend & Icon Meanings": "📖 Legenda do Relatório & Significado dos Ícones",
            "Node & Storage Health": "Saúde do Nó & Armazenamento",
            "Pod Alarms (Section 7)": "Alarmes de Pods (Seção 7)",
            "Cloud & Connectivity": "Nuvem & Conectividade",
            "Normal Status": "Status Normal",
            "Warning: High Usage (>70%)": "Aviso: Uso Alto (>70%)",
            "Critical: Danger (>85%)": "Crítico: Perigo (>85%)",
            "Missing Requests/Limits": "Faltam Requests/Limits",
            "Missing Requests/Limits": "Faltam Requests/Limits",
            "Under-utilized (<5% CPU, <10% RAM) [Above Floor]": "Subutilizado (<5% CPU, <10% RAM) [Acima do Piso]",
            "Normal / Floor (CPU≤50m, RAM≤64Mi)": "Normal / Piso Mínimo (CPU≤50m, RAM≤64Mi)",
            "Close to Limit (>90% of Req)": "Perto do Limite (>90% do Req)",
            "Synced & Healthy": "Sincronizado & Saudável",
            "Connection Error / Node Down": "Erro de Conexão / Nó Fora",
            "Click to view local snapshots": "Clique para ver snapshots locais",
            "End of Report.": "Fim do Relatório.",
            "Save as PDF": "Salvar como PDF"
        };

        /* Sorting Logic */
        function sortTable(n, header) {
            const table = header.closest("table");
            const tbody = table.querySelector("tbody");
            const isAsc = !header.classList.contains("asc");
            
            // 1. Unified Parser using server-side attributes
            function getSortValue(cell) {
                // If data-sort-value exists (generated by AWK), use it directly!
                if (cell.dataset.sortValue) {
                    const attrVal = cell.dataset.sortValue;
                    if (attrVal === "Infinity") return Infinity;
                    const num = parseFloat(attrVal);
                    // Use attribute if valid number, otherwise fall back to text
                    if (!isNaN(num)) return num;
                }
                
                // Fallback for columns without calculated values (e.g. text columns)
                const text = cell.innerText.trim();
                if (!text || text === "-") return -1;
                return text.toLowerCase();
            }

            // 2. Group Rows
            const groups = [];
            let currentGroup = null;
            Array.from(tbody.rows).forEach(row => {
                if (row.classList.contains("detail-row")) {
                    if (currentGroup) currentGroup.details.push(row);
                    else groups.push({ main: row, details: [], isOrphan: true });
                } else {
                    currentGroup = { main: row, details: [], sortValue: getSortValue(row.cells[n]) };
                    groups.push(currentGroup);
                }
            });

            // 3. Sort Groups
            groups.sort((a, b) => {
                if (a.isOrphan || b.isOrphan) return 0;
                const vA = a.sortValue;
                const vB = b.sortValue;
                
                let res = 0;
                if (typeof vA === 'number' && typeof vB === 'number') {
                    res = vA - vB;
                } else {
                    res = String(vA).localeCompare(String(vB));
                }
                return isAsc ? res : -res;
            });

            // 4. Update UI & Appending
            table.querySelectorAll("th").forEach(th => th.classList.remove("asc", "desc"));
            header.classList.toggle("asc", isAsc);
            header.classList.toggle("desc", !isAsc);
            
            groups.forEach(g => {
                tbody.appendChild(g.main);
                g.details.forEach(d => tbody.appendChild(d));
            });
        }

        function initTables() {
            const tables = document.querySelectorAll("table");
            tables.forEach(table => {
                table.classList.add("sortable-table");
                const headers = table.querySelectorAll("th");
                headers.forEach((th, i) => {
                    th.style.cursor = "pointer";
                    th.title = "Click to sort";
                    th.addEventListener("click", () => sortTable(i, th));
                });
            });
        }

        /* Filter & Search Logic */
        function globalSearch() {
            const input = document.getElementById("global-search");
            const filter = input.value.toLowerCase();
            const tables = document.querySelectorAll(".sortable-table");
            let totalMatch = 0;
            let totalRows = 0;

            tables.forEach(table => {
                const rows = table.querySelectorAll("tbody tr");
                rows.forEach(row => {
                    // Skip detail rows (deep-dive) for search? Or include them?
                    // Details rows usually have colspan.
                    if (row.cells.length < 2) return; 

                    const text = row.innerText.toLowerCase();
                    const isMatch = text.includes(filter);
                    row.style.display = isMatch ? "" : "none";
                    if (isMatch) totalMatch++;
                    totalRows++;
                });
            });

            const countEl = document.getElementById("match-count");
            const lang = localStorage.getItem('lang') || 'en';
            if (filter === "") {
                countEl.innerText = lang === 'pt' ? translations["Showing all rows"] : "Showing all rows";
            } else {
                if (lang === 'pt') {
                    countEl.innerText = `${translations["Matched"]} ${totalMatch} ${translations["of"]} ${totalRows} ${translations["rows"]}`;
                } else {
                    countEl.innerText = `Matched ${totalMatch} of ${totalRows} rows`;
                }
            }
        }

        function filterTable(select, colIndex) {
            const filter = select.value.toLowerCase();
            const table = select.closest("table");
            const rows = table.querySelectorAll("tbody tr");

            rows.forEach(row => {
                if (row.cells.length < 2) return; // Skip detail rows
                const cellText = row.cells[colIndex].innerText.toLowerCase();
                const matches = filter === "" || cellText === filter;
                
                // Note: This only works one-filter-at-a-time currently.
                // For multi-filter, we need to track all active filters for the table.
                row.style.display = matches ? "" : "none";
            });
        }

        function populateFilters() {
            const tables = document.querySelectorAll(".sortable-table");
            tables.forEach(table => {
                const headers = table.querySelectorAll("th");
                const rows = Array.from(table.querySelectorAll("tbody tr")).filter(r => r.cells.length > 1);

                headers.forEach((th, i) => {
                    const select = th.querySelector(".filter-select");
                    if (!select) return;

                    // Collect unique values
                    const values = new Set();
                    rows.forEach(row => {
                        const cell = row.cells[i];
                        if (!cell) return;
                        // For complex cells (with tooltips/badges), use textContent but avoid too long values
                        const val = cell.textContent.trim();
                        if (val && val.length < 50) values.add(val);
                    });

                    // Sort and add to select
                    Array.from(values).sort().forEach(val => {
                        const opt = document.createElement("option");
                        opt.value = val;
                        opt.innerText = val;
                        select.appendChild(opt);
                    });
                });
            });
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
            const isPT = lang === 'pt';

            // 1. Static Elements with data-i18n
            document.querySelectorAll('[data-i18n]').forEach(el => {
                const key = el.getAttribute('data-i18n');
                const translation = translations[key];
                
                // Store original text for recovery
                if (!el.dataset.original) el.dataset.original = el.innerText;
                
                if (isPT && translation) el.innerText = translation;
                else el.innerText = el.dataset.original;
            });

            // 2. Placeholders
            document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
                const key = el.getAttribute('data-i18n-placeholder');
                const translation = translations[key];
                if (isPT && translation) el.placeholder = translation;
                else el.placeholder = key;
            });

            // 3. Dynamic content (Tables & Legend)
            // Strategy: Only translate known dictionary keys to preserve icons and special formatting
            const dynElements = document.querySelectorAll('th span, td, .legend-item-row span');
            dynElements.forEach(el => {
                const text = el.innerText.trim();
                if (translations[text]) {
                    if (!el.dataset.original) el.dataset.original = el.innerHTML;
                    if (isPT) el.innerText = translations[text];
                    else el.innerHTML = el.dataset.original;
                }
            });

            // Update search result text context
            globalSearch();
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
                
                // Initialize Tables (Sorting)
                initTables();
 
                // Populate filters
                populateFilters();
 
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

# Restart Python HTTP Server via managed helper
SCRIPT_DIR_INTERNAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR_INTERNAL/report_server.sh" restart

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
