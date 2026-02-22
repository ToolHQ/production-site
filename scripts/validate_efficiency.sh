#!/bin/bash
# scripts/validate_efficiency.sh
# Purpose: Calculate cluster efficiency score.

TOTAL_CAPACITY_M=4000 # 4 nodes * 1000m roughly
TOTAL_REQUESTS_M=0

echo "📊 Calculating Cluster Efficiency..."

# Sum all requests
while read -r REQ; do
    if [[ "$REQ" == *m ]]; then
        VAL="${REQ%m}"
    else
        VAL=$((REQ * 1000))
    fi
    TOTAL_REQUESTS_M=$((TOTAL_REQUESTS_M + VAL))
done < <(kubectl get pods -A -o jsonpath='{range .items[*].spec.containers[*]}{.resources.requests.cpu}{"\n"}{end}' | grep -v '^$')

EFFICIENCY=$(( 100 * TOTAL_REQUESTS_M / TOTAL_CAPACITY_M ))

echo "Total Capacity: ${TOTAL_CAPACITY_M}m"
echo "Total Requests: ${TOTAL_REQUESTS_M}m"
echo "Efficiency Score: ${EFFICIENCY}%"

if [ "$EFFICIENCY" -gt 85 ]; then
    echo "⚠️  WARNING: High Allocation (Risk of Pending Pods)"
elif [ "$EFFICIENCY" -lt 50 ]; then
    echo "⚠️  WARNING: Low Efficiency (Waste)"
else
    echo "✅ HEALTHY"
fi
