#!/bin/bash
# scripts/observability/cluster_health_check.sh
# Cluster Health Watchdog — detects silent failures before they compound.
#
# Designed to run on the master node (kubectl must be configured).
# Invoked by: TUI Health Report (via SSH), systemd timer (locally on master).
#
# Exit codes: 0=healthy or warnings only  2=critical issues present
# (systemd SuccessExitStatus=0 2 — warnings must not mark the timer failed)
# Usage: ./cluster_health_check.sh [--no-color]

set -uo pipefail

# ── Load environment configuration if exists ───────────────────────────────
if [[ -r "/opt/k8s-ops/watchdog.env" ]]; then
    # shellcheck disable=SC1090
    source "/opt/k8s-ops/watchdog.env"
elif [[ -f "/opt/k8s-ops/watchdog.env" ]]; then
    echo "watchdog.env exists but is not readable (fix: install_health_watchdog.sh)" >&2
fi

# ── Color setup ────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--no-color" ]] || [[ ! -t 1 ]]; then
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; NC=''
else
    RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
fi

OK="${GREEN}🟢${NC}"; WARN="${YELLOW}🟡${NC}"; CRIT="${RED}🔴${NC}"

ISSUES=0; WARNINGS=0
CRIT_MESSAGES=()
WARN_MESSAGES=()

report_ok()   { echo -e "  ${OK} ${GREEN}${*}${NC}"; }
report_warn() { echo -e "  ${WARN} ${YELLOW}${*}${NC}"; WARN_MESSAGES+=("${*}"); (( WARNINGS++ )) || true; }
report_crit() { echo -e "  ${CRIT} ${RED}${*}${NC}";   CRIT_MESSAGES+=("${*}"); (( ISSUES++   )) || true; }
section()     { echo -e "\n${BOLD}── ${*} ${NC}"; }

resolve_kubeconfig() {
    local candidate
    local -a candidates=()

    [[ -n "${KUBECONFIG:-}" ]] && candidates+=("$KUBECONFIG")
    candidates+=("/etc/kubernetes/admin.conf" "$HOME/.kube/config" "/home/ubuntu/.kube/config")

    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" && -r "$candidate" ]] || continue
        if KUBECONFIG="$candidate" kubectl version --request-timeout=10s >/dev/null 2>&1; then
            export KUBECONFIG="$candidate"
            return 0
        fi
    done

    return 1
}

# Returns age in seconds for an ISO8601 timestamp (2026-04-03T12:00:00Z)
age_seconds() {
    local ts="$1"
    local epoch_ts epoch_now
    epoch_ts=$(date -d "$ts" +%s 2>/dev/null) || return 1
    epoch_now=$(date -u +%s)
    echo $(( epoch_now - epoch_ts ))
}

fmt_age() {
    local s=$1
    if   (( s < 3600  )); then echo "$((s / 60))m"
    elif (( s < 86400 )); then echo "$((s / 3600))h"
    else echo "$((s / 86400))d"
    fi
}

# ── Header ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  🏥 Cluster Health Report — $(date -u '+%Y-%m-%d %H:%M UTC')${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"

section "Kubectl Access"

if resolve_kubeconfig; then
    report_ok "kubectl API access available via $KUBECONFIG"
else
    report_crit "kubectl API access unavailable: no readable working kubeconfig found"
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  ${CRIT} ${ISSUES} critical, ${WARNINGS} warning(s) — action required${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
    exit 2
fi

# ══════════════════════════════════════════════════════════════════════════
# 1.1  LONGHORN COMPONENT HEALTH
# ══════════════════════════════════════════════════════════════════════════
section "Longhorn Component Health"

# 1.1a  Instance Managers — state must be "running"
bad_im=0
while IFS=$'\t' read -r name state node; do
    [[ -z "$name" ]] && continue
    if [[ "$state" != "running" ]]; then
        report_crit "instance-manager $name on $node: state=$state (expected: running)"
        (( bad_im++ )) || true
    fi
done < <(kubectl get instancemanager.longhorn.io -n longhorn-system \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.currentState}{"\t"}{.spec.nodeID}{"\n"}{end}' \
    2>/dev/null || true)
(( bad_im == 0 )) && report_ok "All Longhorn instance-managers running"

# 1.1b  Engines — state must not be "error"
bad_eng=0
while IFS=$'\t' read -r name state node; do
    [[ -z "$name" ]] && continue
    if [[ "$state" == "error" ]]; then
        report_crit "engine $name on $node: state=error"
        (( bad_eng++ )) || true
    fi
done < <(kubectl get engine.longhorn.io -n longhorn-system \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.currentState}{"\t"}{.status.ownerID}{"\n"}{end}' \
    2>/dev/null || true)
(( bad_eng == 0 )) && report_ok "All Longhorn engines healthy"

# 1.1c  Volumes: faulted robustness
bad_fault=0
while IFS=$'\t' read -r name robust; do
    [[ -z "$name" ]] && continue
    if [[ "$robust" == "faulted" ]]; then
        report_crit "volume $name: robustness=faulted (data at risk)"
        (( bad_fault++ )) || true
    fi
done < <(kubectl get volume.longhorn.io -n longhorn-system \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.robustness}{"\n"}{end}' \
    2>/dev/null || true)
(( bad_fault == 0 )) && report_ok "No Longhorn volumes faulted"

# 1.1d  Volumes: degraded robustness (replica count below spec) — exclude transitional states
bad_deg=0
while IFS=$'\t' read -r name state robust; do
    [[ -z "$name" ]] && continue
    [[ "$robust" != "degraded" ]] && continue
    # Skip transitional states — stateless script cannot determine duration
    [[ "$state" == "attaching" || "$state" == "detaching" || "$state" == "detached" ]] && continue
    report_warn "volume $name: robustness=degraded state=$state (replica count below spec)"
    (( bad_deg++ )) || true
done < <(kubectl get volume.longhorn.io -n longhorn-system \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.state}{"\t"}{.status.robustness}{"\n"}{end}' \
    2>/dev/null || true)
(( bad_deg == 0 )) && report_ok "No attached Longhorn volumes degraded"

# 1.1e  VolumeAttachments stuck attaching > 30 min
# Require an unattached VolumeAttachment, no deletion in progress, and the
# corresponding Longhorn volume still in state=attaching.
THRESH_ATTACH=1800
bad_attach=0
declare -A LONGHORN_VOLUME_STATE=()
while IFS=$'\t' read -r volume_name volume_state; do
    [[ -z "$volume_name" ]] && continue
    LONGHORN_VOLUME_STATE["$volume_name"]="$volume_state"
done < <(kubectl get volume.longhorn.io -n longhorn-system \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.state}{"\n"}{end}' \
    2>/dev/null || true)

while IFS=$'\t' read -r va_name created attached deleting volume_name; do
    [[ -z "$created" || -z "$volume_name" ]] && continue
    [[ "$attached" == "true" ]] && continue
    [[ -n "$deleting" ]] && continue
    [[ "${LONGHORN_VOLUME_STATE[$volume_name]:-unknown}" != "attaching" ]] && continue
    age=$(age_seconds "$created") || continue
    if (( age > THRESH_ATTACH )); then
        report_crit "VolumeAttachment $va_name: volume=$volume_name stuck attaching for $(fmt_age $age) (>30m)"
        (( bad_attach++ )) || true
    fi
done < <(kubectl get volumeattachment \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.creationTimestamp}{"\t"}{.status.attached}{"\t"}{.metadata.deletionTimestamp}{"\t"}{.spec.source.persistentVolumeName}{"\n"}{end}' \
    2>/dev/null || true)
(( bad_attach == 0 )) && report_ok "No VolumeAttachments stuck attaching (>30m)"

# ══════════════════════════════════════════════════════════════════════════
# 1.2  POD STUCK DETECTION
# ══════════════════════════════════════════════════════════════════════════
section "Pod Stuck Detection"

THRESH_STUCK=7200   # 2h  — ContainerCreating / Pending / Init:*
THRESH_ERROR=1800   # 30m — Error state (terminated.finishedAt)
THRESH_RESTART=20   # cumulative restart count proxy for CrashLoop
THRESH_RESTART_ACTIVE=86400  # 24h — ignore historical lifetime restarts with no recent churn

stuck=0; crashloop=0

# ContainerCreating / Pending / Init:* — use pod creationTimestamp
# (pod never reached Running, so creation time is the correct duration proxy)
while IFS=$'\t' read -r ns pod phase reason created; do
    [[ -z "$ns" || -z "$created" ]] && continue
    [[ -z "$reason" ]] && continue
    [[ "$phase" == "Failed" || "$phase" == "Succeeded" ]] && continue
    # Only target stuck-starting states
    case "$reason" in
        ContainerCreating|Pending|*Init*) ;;
        *) continue ;;
    esac
    age=$(age_seconds "$created") || continue
    if (( age > THRESH_STUCK )); then
        report_crit "pod $ns/$pod stuck in $reason for $(fmt_age $age) (>2h)"
        (( stuck++ )) || true
    fi
done < <(kubectl get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.containerStatuses[0].state.waiting.reason}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}' \
    2>/dev/null | grep -v $'\t\t' || true)
# Also catch Pending pods with no containerStatuses yet (never scheduled)
while IFS=$'\t' read -r ns pod phase created; do
    [[ -z "$ns" || "$phase" != "Pending" || -z "$created" ]] && continue
    age=$(age_seconds "$created") || continue
    if (( age > THRESH_STUCK )); then
        report_crit "pod $ns/$pod stuck Pending (unscheduled) for $(fmt_age $age) (>2h)"
        (( stuck++ )) || true
    fi
done < <(kubectl get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}' \
    2>/dev/null || true)

(( stuck == 0 )) && report_ok "No pods stuck in ContainerCreating/Pending/Init (>2h)"

# Error state — use terminated.finishedAt (accurate: pod may have run fine before erroring)
err_pods=0
while IFS=$'\t' read -r ns pod phase term_reason finished; do
    [[ -z "$ns" || -z "$finished" ]] && continue
    [[ "$phase" == "Failed" || "$phase" == "Succeeded" ]] && continue
    [[ "$term_reason" == "Completed" || "$term_reason" == "Evicted" ]] && continue
    age=$(age_seconds "$finished") || continue
    if (( age > THRESH_ERROR )); then
        report_warn "pod $ns/$pod: container terminated/errored $(fmt_age $age) ago (>30m)"
        (( err_pods++ )) || true
    fi
done < <(kubectl get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.containerStatuses[0].state.terminated.reason}{"\t"}{.status.containerStatuses[0].state.terminated.finishedAt}{"\n"}{end}' \
    2>/dev/null | grep -v $'\t$' || true)
(( err_pods == 0 )) && report_ok "No pods in Error/terminated state (>30m)"

# CrashLoop proxy: restartCount > 20 plus active recent restart activity
while IFS=$'\t' read -r ns pod phase ready restarts last_finished started created; do
    [[ -z "$restarts" || "$restarts" == "0" ]] && continue
    (( restarts > THRESH_RESTART )) || continue

    if [[ "$phase" != "Running" || "$ready" != "true" ]]; then
        report_warn "pod $ns/$pod: restartCount=$restarts >20 (CrashLoop proxy; phase=$phase ready=$ready)"
        (( crashloop++ )) || true
        continue
    fi

    # If the pod has been running stably for more than 2 hours, do not flag as crashloop
    if [[ -n "$started" ]]; then
        run_age=$(age_seconds "$started" 2>/dev/null || echo 0)
        if (( run_age > 7200 )); then
            continue
        fi
    fi

    [[ -n "$last_finished" ]] || continue
    age=$(age_seconds "$last_finished" 2>/dev/null) || continue
    if (( age <= THRESH_RESTART_ACTIVE )); then
        report_warn "pod $ns/$pod: restartCount=$restarts >20 (last restart $(fmt_age $age) ago)"
        (( crashloop++ )) || true
    fi
done < <(kubectl get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.containerStatuses[0].ready}{"\t"}{.status.containerStatuses[0].restartCount}{"\t"}{.status.containerStatuses[0].lastState.terminated.finishedAt}{"\t"}{.status.containerStatuses[0].state.running.startedAt}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}' \
    2>/dev/null || true)
(( crashloop == 0 )) && report_ok "No pods with recent excessive restarts (>20)"

# ══════════════════════════════════════════════════════════════════════════
# 1.3  NODE PRESSURE CONDITIONS
# ══════════════════════════════════════════════════════════════════════════
section "Node Pressure Conditions"

declare -A NODE_DISK_PRESSURE=()
node_pressure_alerts=0

while IFS=$'\t' read -r node disk memory pid; do
    [[ -z "$node" ]] && continue
    NODE_DISK_PRESSURE["$node"]="$disk"

    healthy=true
    if [[ "$disk" == "True" ]]; then
        report_crit "node $node: DiskPressure=True (ephemeral-storage pressure active)"
        node_pressure_alerts=$(( node_pressure_alerts + 1 ))
        healthy=false
    fi
    if [[ "$memory" == "True" ]]; then
        report_crit "node $node: MemoryPressure=True"
        node_pressure_alerts=$(( node_pressure_alerts + 1 ))
        healthy=false
    fi
    if [[ "$pid" == "True" ]]; then
        report_crit "node $node: PIDPressure=True"
        node_pressure_alerts=$(( node_pressure_alerts + 1 ))
        healthy=false
    fi

    if [[ "$healthy" == "true" ]]; then
        report_ok "node $node: no pressure conditions"
    fi
done < <(kubectl get nodes -o json 2>/dev/null | jq -r '
    .items[]
    | [
        .metadata.name,
        (.status.conditions[] | select(.type == "DiskPressure") | .status),
        (.status.conditions[] | select(.type == "MemoryPressure") | .status),
        (.status.conditions[] | select(.type == "PIDPressure") | .status)
      ]
    | @tsv' 2>/dev/null || true)

ingress_host_network=$(kubectl -n ingress-nginx get deploy ingress-nginx-controller \
    -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null || true)
ingress_pinned_node=$(kubectl -n ingress-nginx get deploy ingress-nginx-controller -o json 2>/dev/null | \
    jq -r '.spec.template.spec.nodeSelector["kubernetes.io/hostname"] // empty' 2>/dev/null || true)
ingress_external_policy=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath='{.spec.externalTrafficPolicy}' 2>/dev/null || true)

if [[ -n "$ingress_pinned_node" && "${NODE_DISK_PRESSURE[$ingress_pinned_node]:-False}" == "True" ]]; then
    report_crit "ingress-nginx controller pinned to $ingress_pinned_node while node has DiskPressure (hostNetwork=${ingress_host_network:-unknown}, externalTrafficPolicy=${ingress_external_policy:-unknown})"
    node_pressure_alerts=$(( node_pressure_alerts + 1 ))
fi

# ══════════════════════════════════════════════════════════════════════════
# 1.4  CPU HEADROOM PER NODE
# ══════════════════════════════════════════════════════════════════════════
section "CPU Headroom per Node"

# Thresholds (aligned with T-103 Target Policy) - Tuned to prevent false-positives under master resource booking
WARN_PCT=88; CRIT_PCT=95

# Use `kubectl describe node` — gives pre-computed "Requests" line with pct
while IFS= read -r node_name; do
    [[ -z "$node_name" ]] && continue
    # Parse the "cpu   Xm (Y%)" line from Allocated resources section
    alloc_line=$(kubectl describe node "$node_name" 2>/dev/null | \
        awk '/^Allocated resources:/,/^Events:/' | grep '^ *cpu ')
    req_raw=$(echo "$alloc_line"  | awk '{print $2}')  # e.g. 792m
    req_pct=$(echo "$alloc_line"  | awk '{print $3}' | tr -d '(%)')  # e.g. 99
    alloc_raw=$(kubectl get node "$node_name" \
        -o jsonpath='{.status.allocatable.cpu}' 2>/dev/null)

    # Normalize allocatable to millicores
    if [[ "$alloc_raw" == *m ]]; then alloc_m="${alloc_raw%m}"
    else alloc_m=$(( ${alloc_raw:-1} * 1000 )); fi

    # Normalize requested to millicores
    if [[ "$req_raw" == *m ]]; then req_m="${req_raw%m}"
    else req_m=$(( ${req_raw:-0} * 1000 )); fi

    headroom_m=$(( alloc_m - req_m ))
    pct="${req_pct:-$(( req_m * 100 / alloc_m ))}"
    info="${req_m}m/${alloc_m}m (${pct}% used, ${headroom_m}m free)"

    if   (( pct >= CRIT_PCT )); then report_crit "node $node_name: CPU $info"
    elif (( pct >= WARN_PCT )); then report_warn "node $node_name: CPU $info"
    else report_ok "node $node_name: CPU $info"
    fi
done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

# ══════════════════════════════════════════════════════════════════════════
# 1.4  REGISTRY & IMAGE HEALTH
# ══════════════════════════════════════════════════════════════════════════
section "Registry & Image Health"

# Nexus pod readiness
nexus_ready=$(kubectl get pods -n nexus -l app=nexus \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "unknown")
nexus_phase=$(kubectl get pods -n nexus -l app=nexus \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Unknown")

if [[ "$nexus_ready" == "true" && "$nexus_phase" == "Running" ]]; then
    report_ok "Nexus registry: Running and ready"
else
    report_crit "Nexus registry: phase=$nexus_phase ready=$nexus_ready"
fi

# ErrImagePull / ImagePullBackOff > 10 min — use pod creationTimestamp
THRESH_PULL=600
pull_errs=0
while IFS=$'\t' read -r ns pod reason created; do
    [[ -z "$reason" ]] && continue
    case "$reason" in
        ErrImagePull|ImagePullBackOff) ;;
        *) continue ;;
    esac
    age=$(age_seconds "$created") || continue
    if (( age > THRESH_PULL )); then
        report_crit "pod $ns/$pod: $reason for $(fmt_age $age) (>10m)"
        (( pull_errs++ )) || true
    fi
done < <(kubectl get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.containerStatuses[0].state.waiting.reason}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}' \
    2>/dev/null || true)
(( pull_errs == 0 )) && report_ok "No image pull errors (>10m)"

# ══════════════════════════════════════════════════════════════════════════
# 1.5  LONGHORN NODE DISK HEALTH  (T-104)
# ══════════════════════════════════════════════════════════════════════════
section "Longhorn Node Disk Health"

DISK_WARN_BYTES=$(( 15 * 1024 * 1024 * 1024 ))   # 15 GB
DISK_CRIT_BYTES=$(( 10 * 1024 * 1024 * 1024 ))   # 10 GB

while IFS=$'\t' read -r node schedulable avail; do
    [[ -z "$node" ]] && continue
    avail_gb=$(( avail / 1024 / 1024 / 1024 ))
    if [[ "$schedulable" != "true" ]]; then
        report_crit "Longhorn disk on $node: schedulable=false (no new replicas can be placed)"
    elif (( avail < DISK_CRIT_BYTES )); then
        report_crit "Longhorn disk on $node: ${avail_gb} GB available (<10 GB critical)"
    elif (( avail < DISK_WARN_BYTES )); then
        report_warn "Longhorn disk on $node: ${avail_gb} GB available (<15 GB warning)"
    else
        report_ok "Longhorn disk on $node: ${avail_gb} GB available"
    fi
done < <(kubectl get node.longhorn.io -n longhorn-system -o json 2>/dev/null | \
    jq -r '.items[] | [
        .metadata.name,
        (.spec.disks | to_entries[0].value.allowScheduling | tostring),
        (.status.diskStatus | to_entries[0].value.storageAvailable | tostring)
    ] | @tsv' 2>/dev/null || true)

# ══════════════════════════════════════════════════════════════════════════
# PKI — Certificate Expiry & Chain Integrity
# ══════════════════════════════════════════════════════════════════════════
section "PKI — Certificate Expiry & Chain Integrity"

NOW_EPOCH=$(date +%s)

# Check all cert-manager Certificate resources
while IFS='|' read -r CERT_NAME CERT_NS NOT_AFTER SECRET_NAME; do
    [[ -z "$CERT_NAME" ]] && continue

    EXPIRY_EPOCH=$(date -d "$NOT_AFTER" +%s 2>/dev/null || echo 0)
    if (( EXPIRY_EPOCH == 0 )); then
        report_warn "cert $CERT_NS/$CERT_NAME — could not parse notAfter: $NOT_AFTER"
        continue
    fi

    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

    if (( DAYS_LEFT < 7 )); then
        report_crit "cert $CERT_NS/$CERT_NAME — expires in ${DAYS_LEFT}d ($NOT_AFTER)"
    elif (( DAYS_LEFT < 30 )); then
        report_warn "cert $CERT_NS/$CERT_NAME — expires in ${DAYS_LEFT}d ($NOT_AFTER)"
    else
        report_ok  "cert $CERT_NS/$CERT_NAME — expires in ${DAYS_LEFT}d"
    fi

    # Chain integrity: TLS secret must have >= 2 certs
    if [[ -n "$SECRET_NAME" ]]; then
        TLS_CRT=$(kubectl get secret "$SECRET_NAME" -n "$CERT_NS" \
            -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null || true)
        CERT_COUNT=$(echo "$TLS_CRT" | grep -c "BEGIN CERTIFICATE" 2>/dev/null || echo 0)
        if (( CERT_COUNT < 2 )); then
            report_warn "chain $CERT_NS/$SECRET_NAME — incomplete chain (${CERT_COUNT} cert). chain-repair will fix at 02:00 UTC"
        fi
    fi

done < <(kubectl get certificates -A \
    -o jsonpath='{range .items[*]}{.metadata.name}|{.metadata.namespace}|{.status.notAfter}|{.spec.secretName}{"\n"}{end}' \
    2>/dev/null || true)


echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
if   (( ISSUES == 0 && WARNINGS == 0 )); then
    echo -e "${BOLD}${GREEN}  ✅ All checks passed — cluster healthy${NC}"
elif (( ISSUES == 0 )); then
    echo -e "${BOLD}${YELLOW}  🟡 $WARNINGS warning(s) — review recommended${NC}"
else
    echo -e "${BOLD}${RED}  🔴 $ISSUES critical, $WARNINGS warning(s) — action required${NC}"
fi
echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
echo ""

send_notifications() {
    local url="${WATCHDOG_WEBHOOK_URL:-}"
    if [[ -z "$url" ]]; then
        return 0
    fi

    if (( ISSUES == 0 && WARNINGS == 0 )); then
        return 0
    fi

    echo "Sending health notification to webhook..."

    local status_text
    if (( ISSUES > 0 )); then
        status_text="🔴 CRITICAL"
    else
        status_text="🟡 WARNING"
    fi

    local content
    content="### 🏥 **Cluster Health Watchdog Alert!**\n"
    content+="**Cluster**: \`oci-k8s-cluster\`\n"
    content+="**Status**: ${status_text}\n"
    content+="Detected **${ISSUES} critical issue(s)** and **${WARNINGS} warning(s)**.\n\n"

    if (( ${#CRIT_MESSAGES[@]} > 0 )); then
        content+="**🔴 Critical Issues:**\n"
        for msg in "${CRIT_MESSAGES[@]}"; do
            content+="- ${msg}\n"
        done
        content+="\n"
    fi

    if (( ${#WARN_MESSAGES[@]} > 0 )); then
        content+="**🟡 Warnings:**\n"
        for msg in "${WARN_MESSAGES[@]}"; do
            content+="- ${msg}\n"
        done
        content+="\n"
    fi

    # Format JSON payload safely using jq
    local payload
    payload=$(jq -n --arg msg "$(echo -e "$content")" '{"content": $msg}')

    curl -s -X POST -H "Content-Type: application/json" -d "$payload" "$url" >/dev/null || true
}

# Send any pending webhook notifications before exiting
send_notifications

# Exit 2=critical only; warnings stay 0 so systemd timer stays healthy
(( ISSUES > 0 )) && exit 2
exit 0
