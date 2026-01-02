#!/usr/bin/env bash
# scripts/maintenance/clean_cluster_chaos.sh

# Wrap kubectl
k_cmd="kubectl"
if type run_kubectl >/dev/null 2>&1; then
    k_cmd="run_kubectl"
fi

echo -e "${YELLOW}🧹 Cleaning Cluster Chaos...${NC}"

# Get all namespaces
namespaces=$($k_cmd get ns -o jsonpath='{.items[*].metadata.name}')

for ns in $namespaces; do
    # Count targets first
    count=$($k_cmd get pods -n "$ns" --field-selector=status.phase!=Running,status.phase!=Pending -o jsonpath='{.items[*].metadata.name}' | wc -w)
    
    if [ "$count" -gt 0 ]; then
        echo -e "   • Namespace ${CYAN}$ns${NC}: Found ${RED}$count${NC} failed pods. Cleaning..."
        
        # Delete Evicted
        $k_cmd delete pods -n "$ns" --field-selector=status.reason=Evicted --wait=false 2>/dev/null
        
        # Delete Error/Completed (Failed phase)
        $k_cmd delete pods -n "$ns" --field-selector=status.phase=Failed --wait=false 2>/dev/null
        
        # Delete Succeeded (Completed jobs)
        $k_cmd delete pods -n "$ns" --field-selector=status.phase=Succeeded --wait=false 2>/dev/null
    fi
done

echo -e "${GREEN}✨ Cleanup complete!${NC}"
