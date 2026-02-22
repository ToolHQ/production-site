#!/bin/bash
# scripts/audit_resources.sh
# Purpose: Dump precise resource allocation vs usage for Zero-Waste analysis.

OUTPUT_FILE="resource_audit.csv"
echo "Namespace,Pod,Container,CPU_Req_m,CPU_Lim_m,CPU_Usage_m,Mem_Req_Mi,Mem_Lim_Mi,Mem_Usage_Mi" > "$OUTPUT_FILE"

echo "🔍 Collecting Pod Metrics (this may take a moment)..."

# Get current usage snapshot
kubectl top pods -A --containers --no-headers > /tmp/pod_metrics.txt

# Iterate all pods
kubectl get pods -A -o json | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | while read -r NS POD; do
    
    # Get Pod Spec
    POD_JSON=$(kubectl get pod -n "$NS" "$POD" -o json)
    
    # Iterate Containers
    echo "$POD_JSON" | jq -r '.spec.containers[] | .name' | while read -r CONTAINER; do
        
        # Extract Requests/Limits (Default to 0 if missing)
        CPU_REQ=$(echo "$POD_JSON" | jq -r --arg c "$CONTAINER" '.spec.containers[] | select(.name==$c) | .resources.requests.cpu // "0"')
        CPU_LIM=$(echo "$POD_JSON" | jq -r --arg c "$CONTAINER" '.spec.containers[] | select(.name==$c) | .resources.limits.cpu // "0"')
        MEM_REQ=$(echo "$POD_JSON" | jq -r --arg c "$CONTAINER" '.spec.containers[] | select(.name==$c) | .resources.requests.memory // "0"')
        MEM_LIM=$(echo "$POD_JSON" | jq -r --arg c "$CONTAINER" '.spec.containers[] | select(.name==$c) | .resources.limits.memory // "0"')

        # Normalize CPU to millicores
        if [[ "$CPU_REQ" == *m ]]; then CPU_REQ="${CPU_REQ%m}"; else CPU_REQ=$((CPU_REQ * 1000)); fi
        if [[ "$CPU_LIM" == *m ]]; then CPU_LIM="${CPU_LIM%m}"; else CPU_LIM=$((CPU_LIM * 1000)); fi
        
        # Normalize Mem to Mi (rough approx: 1Gi = 1000Mi for simplicity in bash, or handle units)
        # Using simple sed for common units, robust normalization would use a helper.
        # Check for Mi, Gi, Ki.
        normalize_mem() {
            local val=$1
            if [[ "$val" == "0" ]]; then echo "0"; return; fi
            if [[ "$val" == *Gi ]]; then echo "$(( ${val%Gi} * 1024 ))"; return; fi
            if [[ "$val" == *Mi ]]; then echo "${val%Mi}"; return; fi
            if [[ "$val" == *Ki ]]; then echo "$(( ${val%Ki} / 1024 ))"; return; fi
            # raw bytes
            echo "$(( val / 1024 / 1024 ))"
        }

        MEM_REQ_NORM=$(normalize_mem "$MEM_REQ")
        MEM_LIM_NORM=$(normalize_mem "$MEM_LIM")

        # Get Usage from metrics snapshot
        METRICS=$(grep "$NS" /tmp/pod_metrics.txt | grep "$POD" | grep "$CONTAINER")
        if [ -z "$METRICS" ]; then
            CPU_USE="0"
            MEM_USE="0"
        else
            CPU_USE=$(echo "$METRICS" | awk '{print $3}')
            MEM_USE=$(echo "$METRICS" | awk '{print $4}')
            # Normalize Usage
            if [[ "$CPU_USE" == *m ]]; then CPU_USE="${CPU_USE%m}"; else CPU_USE="0"; fi # unexpected format
            if [[ "$MEM_USE" == *Mi ]]; then MEM_USE="${MEM_USE%Mi}"; else MEM_USE="0"; fi
        fi

        echo "$NS,$POD,$CONTAINER,$CPU_REQ,$CPU_LIM,$CPU_USE,$MEM_REQ_NORM,$MEM_LIM_NORM,$MEM_USE" >> "$OUTPUT_FILE"
    done
done

echo "✅ Audit Complete. Saved to $OUTPUT_FILE"
