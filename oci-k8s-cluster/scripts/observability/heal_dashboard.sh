#!/usr/bin/env bash
# scripts/observability/heal_dashboard.sh
# Automates diagnosis and repair of Kubernetes Dashboard 503 errors

heal_dashboard() {
    local dashboard_ns="kubernetes-dashboard"
    local kong_label="app.kubernetes.io/name=kong"
    
    # Define execution wrapper: use run_kubectl if available (sourced), else default to local kubectl
    local k_cmd="kubectl"
    if type run_kubectl >/dev/null 2>&1; then
        k_cmd="run_kubectl"
    fi

    echo -e "${YELLOW}🔍 Checking Dashboard health...${NC}"

    # 1. Check if Kong pod is crashing
    local kong_pod
    kong_pod=$($k_cmd get pod -n "$dashboard_ns" -l "$kong_label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$kong_pod" ]; then
        echo -e "${RED}❌ Kong pod not found in namespace $dashboard_ns${NC}"
        return 1
    fi

    local pod_status
    pod_status=$($k_cmd get pod -n "$dashboard_ns" "$kong_pod" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)

    if [[ "$pod_status" == "CrashLoopBackOff" || "$pod_status" == "Error" ]]; then
        echo -e "${RED}⚠️  Dashboard instability detected: Kong pod is in $pod_status${NC}"
        
        # 2. Check logs for the specific "Address already in use" error
        # Note: logs via ssh might capture stderr differently, but run_kubectl usually handles it.
        if $k_cmd logs -n "$dashboard_ns" "$kong_pod" --tail=20 2>&1 | grep -q "Address already in use"; then
            echo -e "${YELLOW}🛠️  Diagnosis: Stale socket file detected (Kong Gateway bug).${NC}"
            echo -e "${YELLOW}⚡ Attempting auto-fix: Force deleting pod to clear ephemeral storage...${NC}"
            
            $k_cmd delete pod -n "$dashboard_ns" "$kong_pod" --force --grace-period=0
            
            echo -e "${YELLOW}⏳ Waiting for pod to restart...${NC}"
            # For wait, we might need a tighter loop or just wait a bit since kubectl wait via ssh might be flaky with timeouts
            sleep 5
            if $k_cmd wait --for=condition=ready pod -n "$dashboard_ns" -l "$kong_label" --timeout=60s >/dev/null 2>&1; then
                echo -e "${GREEN}✅ Fix successful! Dashboard is restarting.${NC}"
                return 0
            else
                echo -e "${RED}❌ Auto-fix timed out. Please check manually.${NC}"
                return 1
            fi
        else
            echo -e "${RED}❌ Kong is crashing, but not due to the known socket issue. Manual investigation required.${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}✅ Dashboard components appear healthy.${NC}"
        return 0
    fi
}
