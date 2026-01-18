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
# CLUSTER_NODES=("oci-k8s-master" "oci-k8s-node-1" "oci-k8s-node-2" "oci-k8s-node-3")
CLUSTER_NODES=("oci-k8s-master" "oci-k8s-node-1" "oci-k8s-node-2" "oci-k8s-node-3")
OUTPUT_DIR="./reports/inventory_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
TEMP_DIR=$(mktemp -d)
# trap "rm -rf $TEMP_DIR" EXIT

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
    
    # System = Used - (LH + Cont + Logs + Etcd + Backup + Minio)
    known=$((lh + cont + logs + etcd + backup + minio))
    system=$((root_used - known))
    if [ "$system" -lt 0 ]; then system=0; fi
    
    # Output raw values (1k blocks) for report generator to format
    # Format: STATS|PCT|TOTAL|USED|LH|DOCKER|LOGS|ETCD|BACKUP|SYSTEM|MINIO
    echo "STATS|$root_pct|$root_total|$root_used|$lh|$cont|$logs|$etcd|$backup|$system|$minio"
    
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
ssh -T -o StrictHostKeyChecking=no oci-k8s-master "sudo du -sh /data/minio/* 2>/dev/null" > "$TEMP_DIR/minio_usage.txt" &
PIDS+=($!)

# ------------------------------------------------------------------------------
# 3. GDRIVE AUDIT (Remote rclone on Master)
# ------------------------------------------------------------------------------
echo -e "${YELLOW}☁️  Auditing Google Drive...${NC}"
# Use rclone size for accurate sizing
ssh -T -o StrictHostKeyChecking=no oci-k8s-master "sudo rclone lsd gdrive:k8s-backups --config /root/.config/rclone/rclone.conf | awk '{print \$5}' | while read folder; do size=\$(sudo rclone size gdrive:k8s-backups/\$folder --config /root/.config/rclone/rclone.conf --json | jq .bytes | numfmt --to=iec); echo \"\$folder \$size\"; done" > "$TEMP_DIR/gdrive_usage.txt" 2>&1 &
PIDS+=($!)

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
    echo "| Folder | Real Size | Status |"
    echo "|---|---|---|"
    if [ -s "$TEMP_DIR/gdrive_usage.txt" ]; then
        while read -r line; do
            FOLDER=$(echo "$line" | awk '{print $1}')
            SIZE=$(echo "$line" | awk '{print $2}')
            echo "| $FOLDER | $SIZE | ✅ Synced |"
        done < "$TEMP_DIR/gdrive_usage.txt"
    else
        echo "| Error | - | ❌ Unreachable |"
    fi
    echo ""
    
    echo "## 2. Minio Object Storage (Local)"
    echo "| Bucket | Size |"
    echo "|---|---|"
    if [ -s "$TEMP_DIR/minio_usage.txt" ]; then
        while read -r line; do
            SIZE=$(echo "$line" | cut -f1)
            OBJ_PATH=$(echo "$line" | cut -f2)
            BUCKET=$(basename "$OBJ_PATH")
            echo "| $BUCKET | $SIZE |"
        done < "$TEMP_DIR/minio_usage.txt"
    else
         echo "| No Data | - |"
    fi
    echo ""

    echo "## 3. Node Inventory & Orphans (Potential Cleanup)"
    echo "> **Note:** Scans directories: /home, /root, /tmp, /data. Excludes active backups."
    echo ""
    
    # Table Header
    echo "| Node | Usage | Size | Longhorn | Docker | Logs | Etcd | Backup | System |"
    echo "|---|---|---|---|---|---|---|---|---|"
    
    for node in "${CLUSTER_NODES[@]}"; do
        if [ -f "$TEMP_DIR/$node.txt" ]; then
            # Parse STATS line
            stats_line=$(grep "^STATS|" "$TEMP_DIR/$node.txt" || echo "")
            
            if [ -n "$stats_line" ]; then
                 IFS='|' read -r _tag pct total used lh cont logs etcd backup system minio <<< "$stats_line"
                 
                 # Helper to format kilobytes to human
                 fmt_kb() {
                     numfmt --to=iec --from-unit=1024 "$1" 2>/dev/null || echo "0B"
                 }
                 
                 # Default values to 0 to prevent JS syntax errors
                 lh=${lh:-0}
                 cont=${cont:-0}
                 logs=${logs:-0}
                 etcd=${etcd:-0}
                 backup=${backup:-0}
                 system=${system:-0}
                 minio=${minio:-0}
                 
                 h_total=$(fmt_kb "$total")
                 h_lh=$(fmt_kb "$lh")
                 h_cont=$(fmt_kb "$cont")
                 h_logs=$(fmt_kb "$logs")
                 [ "$etcd" -gt 0 ] && h_etcd=$(fmt_kb "$etcd") || h_etcd="-"
                 [ "$backup" -gt 0 ] && h_backup=$(fmt_kb "$backup") || h_backup="-"
                 h_system=$(fmt_kb "$system")
                 
                 # Status Icon based on PCT
                 clean_pct=${pct%\%}
                 status_icon="🟢"
                 if [ "$clean_pct" -gt 85 ]; then status_icon="🔴"; elif [ "$clean_pct" -gt 70 ]; then status_icon="🟡"; fi
                 
                 echo "| **$node** | $status_icon $pct | $h_total | $h_lh | $h_cont | $h_logs | $h_etcd | $h_backup | $h_system |"
                 
                 # Save for Charts (Raw Bytes)
                 # Format: NODE|TOTAL|USED|LH|CONT|LOGS|ETCD|BACKUP|SYSTEM|MINIO
                 echo "$node|$total|$used|$lh|$cont|$logs|$etcd|$backup|$system|$minio" >> "$TEMP_DIR/charts.dat"
                 
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
    done
    
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
    <title>Storage Inventory</title>
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
        h3 { color: var(--text-muted); margin-top: 25px; }

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
        
        <div id="chart-section" style="margin-top: 30px; display:none;">
            <h2>📊 Storage Distribution (Visual)</h2>
            <div id="charts-area" class="chart-grid"></div>
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
BEGIN { in_table=0; in_code=0 }
/^```/ { 
    if (in_code) { print "</pre>"; in_code=0 } 
    else { print "<pre>"; in_code=1 } 
    next 
}
/^\|/ { 
    if ($0 ~ /^\|[-|: ]+\|$/) next
    if (!in_table) { print "<table>"; in_table=1 }
    print "<tr>"
    n=split($0, a, "|")
    for (i=2; i<n; i++) {
        # Check if header row (separator line usually follows)
        # Simplified: first row is treated as header in this logic roughly
        gsub(/^ +| +$/, "", a[i])
        print "<td>" a[i] "</td>" 
    }
    print "</tr>"
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
END { if (in_table) print "</table>" }
' >> "$HTML_FILE"

# Prepare Chart Data JS
CHART_JS_DATA="const chartData = ["
if [ -f "$TEMP_DIR/charts.dat" ]; then
    while read -r line; do
        IFS='|' read -r node total used lh cont logs etcd backup system minio <<< "$line"
        # Calculate Free
        free=$((total - used))
        CHART_JS_DATA="${CHART_JS_DATA}{node:'${node}',lh:${lh},docker:${cont},logs:${logs},etcd:${etcd},backup:${backup},system:${system},minio:${minio},free:${free}},"
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

        function toggleTheme() {
            const html = document.documentElement;
            const current = html.getAttribute('data-theme');
            const next = current === 'dark' ? 'light' : 'dark';
            html.setAttribute('data-theme', next);
            localStorage.setItem('theme', next);
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
                const labels = ['Docker (Cleanable)', 'Logs (Cleanable)', 'Longhorn (PVs)', 'System', 'Minio (Data)', 'Etcd', 'Backup', 'Free'];
                const values = [data.docker, data.logs, data.lh, data.system, data.minio, data.etcd, data.backup, data.free];
                const colors = [
                    '#e74c3c', // Docker
                    '#d35400', // Logs
                    '#3498db', // Longhorn
                    '#7f8c8d', // System
                    '#95a5a6', // Minio
                    '#bdc3c7', // Etcd
                    '#2ecc71', // Backup
                    '#ecf0f1'  // Free
                ];
                
                // Generate Sorted Data for Legend
                let sortedData = labels.map((label, i) => ({
                    label: label,
                    value: values[i],
                    color: colors[i]
                })).sort((a, b) => b.value - a.value); // Descending
                
                // Build Legend HTML
                let legendHtml = '';
                sortedData.forEach(item => {
                    legendHtml += '<div class="legend-item"><span class="legend-label"><span class="legend-color" style="background:' + item.color + '"></span>' + item.label + '</span><span class="legend-value">' + fmtBytes(item.value) + '</span></div>';
                });
                legend.innerHTML = legendHtml;
                
                // Render Chart
                new Chart(canvas, {
                    type: 'doughnut',
                    data: {
                        labels: labels,
                        datasets: [{
                            data: values,
                            backgroundColor: colors,
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
                                        return context.label + ': ' + fmtBytes(context.raw);
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
            }, 50);
        })();
    </script>
</body>
</html>
EOF

echo -e "${GREEN}✨ Reports Generated:${NC}"
echo -e "   📄 Markdown: $MD_FILE"
echo -e "   🌐 HTML (PDF Ready): $HTML_FILE"
echo -e ""
echo -e "${BOLD}Use 'Save as PDF' in your browser to export the HTML report.${NC}"

# ------------------------------------------------------------------------------
# 7. SERVE REPORT (Temporary Web Server)
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}🏁 Processing Complete!${NC}"
echo -e "${YELLOW}Starting temporary web server to view report...${NC}"

# Get primary IP
HOST_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}👉 Local:   http://localhost:8000/inventory.html${NC}"
[ -n "$HOST_IP" ] && echo -e "${GREEN}👉 Network: http://${HOST_IP}:8000/inventory.html${NC}"
echo -e "${GRAY}(Press Ctrl+C to stop)${NC}"

cd "$OUTPUT_DIR"
# Python 3 http.server
python3 -m http.server 8000 >/dev/null 2>&1
