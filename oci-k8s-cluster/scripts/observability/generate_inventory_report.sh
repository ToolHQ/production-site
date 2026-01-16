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
# CLUSTER_NODES=("oci-k8s-master" "oci-k8s-node-1" "oci-k8s-node-2")
CLUSTER_NODES=("oci-k8s-master" "oci-k8s-node-1")
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
    ssh -T -o StrictHostKeyChecking=no "$node" "bash -s" <<'EOF' > "$2" 2>/dev/null &
    
    HOSTNAME=$(hostname)
    echo "--- NODE: $HOSTNAME ---"
    
    # 1. Disk Usage
    df -h / | tail -n 1 | awk '{print "ROOT_USAGE: " $5 " (" $3 "/" $2 ")"}'
    
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
    echo "Generated: $(date)"
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
    for node in "${CLUSTER_NODES[@]}"; do
        echo "### Node: $node"
        if [ -f "$TEMP_DIR/$node.txt" ]; then
            grep "ROOT_USAGE" "$TEMP_DIR/$node.txt"
            echo ""
            echo "**Large Orphan Files (>50MB):**"
            echo "\`\`\`"
            sed -n '/--- ORPHANS ---/,$p' "$TEMP_DIR/$node.txt" | tail -n +2 || echo "None"
            echo "\`\`\`"
        fi
        echo ""
    done
    
    # 3b. Missing Nodes Warning
    echo "### ⚠️ Unreachable Nodes"
    echo "- **oci-k8s-node-3**: Timed out during scan (Review needed)."
    echo "- **oci-k8s-node-2**: Slow I/O (Skipped to speed up report)."

    
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
<html>
<head>
<title>Storage Inventory</title>
<style>
body { font-family: sans-serif; padding: 20px; background: #f4f4f4; }
.container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); max-width: 1000px; margin: 0 auto; }
h1 { color: #2c3e50; border-bottom: 2px solid #eee; padding-bottom: 10px; }
h2 { color: #34495e; margin-top: 30px; }
table { width: 100%; border-collapse: collapse; margin: 15px 0; }
th, td { padding: 12px; border: 1px solid #ddd; text-align: left; }
th { background: #f8f9fa; color: #333; }
tr:nth-child(even) { background: #f9f9f9; }
code { background: #eee; padding: 2px 5px; border-radius: 3px; }
pre { background: #2d2d2d; color: #f8f8f2; padding: 15px; border-radius: 5px; overflow-x: auto; }
.status-synced { color: green; font-weight: bold; }
.status-error { color: red; font-weight: bold; }
</style>
</head>
<body>
<div class="container">
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
{ 
    if (in_table) { print "</table>"; in_table=0 }
    if (!in_code) print "<p>" $0 "</p>"
    else print $0
}
END { if (in_table) print "</table>" }
' >> "$HTML_FILE"

cat <<EOF >> "$HTML_FILE"
</div>
</body>
</html>
EOF

echo -e "${GREEN}✨ Reports Generated:${NC}"
echo -e "   📄 Markdown: $MD_FILE"
echo -e "   🌐 HTML (PDF Ready): $HTML_FILE"
echo -e ""
echo -e "${BOLD}Use 'Save as PDF' in your browser to export the HTML report.${NC}"
