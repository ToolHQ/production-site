#!/bin/bash
# list_images.sh
# Fetches container images from a node via crictl, sorted by size (largest first).
# Usage: ./list_images.sh <node_name>

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Go up one level to find vm_utils.sh
source "$SCRIPT_DIR/../volume_manager/vm_utils.sh"

NODE=$1

if [ -z "$NODE" ]; then
    echo "Usage: $0 <node_name>"
    exit 1
fi

# Fetch both Images and Running Containers (ImageRefs) in one go to be atomic and fast
# We use a compound command on the remote side
DATA=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$NODE" "bash -c 'sudo crictl ps -o json; echo \"__SEPARATOR__\"; sudo crictl images -o json'" 2>/dev/null)

if [ -z "$DATA" ]; then
    echo "Error: Failed to fetch data from $NODE" >&2
    exit 1
fi

# Split data
CONTAINERS_JSON=$(echo "$DATA" | sed -n '/^__SEPARATOR__$/q;p')
IMAGES_JSON=$(echo "$DATA" | sed -n '/^__SEPARATOR__$/,$p' | tail -n +2)

# Extract Used Image IDs into a lookup string (space separated)
USED_IDS=$(echo "$CONTAINERS_JSON" | jq -r '.containers[]?.imageRef' | sort | uniq | tr '\n' ' ')

# Sort Mode
# If 2nd argument is provided and contains "safe", enable safe sort
SORT_ARG=$2
SORT_MODE="size"
if [[ -f "$SORT_ARG" ]]; then
    if grep -q "safe" "$SORT_ARG"; then
        SORT_MODE="safe"
    fi
elif [[ "$SORT_ARG" == "--sort-safe" ]]; then
    SORT_MODE="safe"
fi

# Pipeline
# 1. JQ extracts raw fields: Size, ShortID, Tag, FullID
# 2. AWK adds Status and Sort Keys
#    Output: SORT_WEIGHT RAW_SIZE HumanSize ShortID Status Tag FullID
# 3. SORT based on mode
# 4. CUT to remove sort keys

awk_logic='
BEGIN {
    split(used_ids, arr, " ");
    for (i in arr) used[arr[i]] = 1;
}
function human(x) {
    if (x<1024) return x" B";
    x/=1024;
    if (x<1024) return sprintf("%.1f KiB", x);
    x/=1024;
    if (x<1024) return sprintf("%.1f MiB", x);
    x/=1024;
    return sprintf("%.1f GiB", x);
}
{
    size=$1; id=$2; tag=$3; full_id=$4;
    
    status="⚪ (Unused)";
    weight=2; # Default: Unused (Medium Priority)
    
    if (full_id in used) {
        status="🟢 (In Use)";
        weight=3; # In Use (Lowest Priority for cleanup)
    } else if (tag == "<none>") {
        status="🧹 (Dangling)";
        weight=1; # Dangling (Highest Priority for cleanup)
    }
    
    # Output columns (Tab separated for easy cut)
    # Weight, Size, Human, ID, Status, Tag, FullID
    printf "%d\t%d\t%-10s %-15s %-12s %s\t%s\n", weight, size, human(size), substr(id, 8, 12), status, tag, full_id
}'

# Construct Sort Command
if [ "$SORT_MODE" == "safe" ]; then
    # Sort by Weight Ascending (1->3), then Size Descending
    SORT_CMD="sort -t $'\t' -k1,1n -k2,2rn"
else
    # Sort by Size Descending only
    SORT_CMD="sort -t $'\t' -k2,2rn"
fi

echo "$IMAGES_JSON" | jq -r '.images[] | "\(.size) \(.id) \((.repoTags[0] // "<none>") ) \( .id )"' | \
awk -v used_ids="$USED_IDS" "$awk_logic" | \
eval "$SORT_CMD" | \
cut -f3-
