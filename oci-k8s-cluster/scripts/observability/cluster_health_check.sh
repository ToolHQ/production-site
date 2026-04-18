#!/bin/bash
# scripts/observability/cluster_health_check.sh
# Cluster Health Watchdog — detects silent failures before they compound.
#
# Designed to run on the master node (kubectl must be configured).
# Invoked by: TUI Health Report (via SSH), systemd timer (locally on master).
#
# Exit codes: 0=healthy  1=warnings only  2=critical issues present
# Usage: ./cluster_health_check.sh [--no-color]

set -uo pipefail

# ── Color setup ────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--no-color" ]] || [[ ! -t 1 ]]; then
    RED=''; YELLOW=''; GREEN=''; CYAN=''; BOLD=''; NC=''
else
    RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
fi

OK="${GREEN}🟢${NC}"; WARN="${YELLOW}🟡${NC}"; CRIT="${RED}🔴${NC}"

ISSUES=0; WARNINGS=0

report_ok()   { echo -e "  ${OK} ${GREEN}${*}${NC}"; }
report_warn() { echo -e "  ${WARN} ${YELLOW}${*}${NC}"; (( WARNINGS++ )) || true; }
report_crit() { echo -e "  ${CRIT} ${RED}${*}${NC}";   (( ISSUES++   )) || true; }
section()     { echo -e "\n${BOLD}── ${*} ${NC}"; }

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
# Uses VolumeAttachment creationTimestamp — avoids stateless limitation
THRESH_ATTACH=1800
bad_attach=0
while IFS=$'\t' read -r va_name created attached; do
    [[ -z "$created" ]] && continue
    [[ "$attached" == "true" ]] && continue
    age=$(age_seconds "$created") || continue
    if (( age > THRESH_ATTACH )); then
        report_crit "VolumeAttachment $va_name: stuck attaching for $(fmt_age $age) (>30m)"
        (( bad_attach++ )) || true
    fi
done < <(kubectl get volumeattachment \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.creationTimestamp}{"\t"}{.status.attached}{"\n"}{end}' \
    2>/dev/null || true)
(( bad_attach == 0 )) && report_ok "No VolumeAttachments stuck attaching (>30m)"

# ══════════════════════════════════════════════════════════════════════════
# 1.2  POD STUCK DETECTION
# ══════════════════════════════════════════════════════════════════════════
section "Pod Stuck Detection"

THRESH_STUCK=7200   # 2h  — ContainerCreating / Pending / Init:*
THRESH_ERROR=1800   # 30m — Error state (terminated.finishedAt)
THRESH_RESTART=20   # cumulative restart count proxy for CrashLoop

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

# CrashLoop proxy: restartCount > 20 (kubectl only exposes cumulative count)
while IFS=$'\t' read -r ns pod restarts created; do
    [[ -z "$restarts" || "$restarts" == "0" ]] && continue
    if (( restarts > THRESH_RESTART )); then
        age=$(age_seconds "$created" 2>/dev/null) && age_str="age=$(fmt_age $age)" || age_str=""
        report_warn "pod $ns/$pod: restartCount=$restarts >20 (CrashLoop proxy; $age_str)"
        (( crashloop++ )) || true
    fi
done < <(kubectl get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.containerStatuses[0].restartCount}{"\t"}{.metadata.creationTimestamp}{"\n"}{end}' \
    2>/dev/null || true)
(( crashloop == 0 )) && report_ok "No pods with excessive restarts (>20)"

# ══════════════════════════════════════════════════════════════════════════
# 1.3  CPU HEADROOM PER NODE
# ══════════════════════════════════════════════════════════════════════════
section "CPU Headroom per Node"

# Thresholds (aligned with T-103 Target Policy)
WARN_PCT=75; CRIT_PCT=85

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

# Exit 2=critical, 1=warnings, 0=healthy
(( ISSUES   > 0 )) && exit 2
(( WARNINGS > 0 )) && exit 1
exit 0
