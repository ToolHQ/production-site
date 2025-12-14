#!/bin/bash
# lib/audit.sh
# Provides audit logging capabilities for K8s Ops TUI
# Logs are stored in /var/log/k8s_ops.log

AUDIT_LOG_FILE="/var/log/k8s_ops.log"

# Ensure log file is writable by current user
# If not, we try to create it or fall back to home dir
ensure_audit_log_access() {
    if [ ! -w "$AUDIT_LOG_FILE" ]; then
        if sudo touch "$AUDIT_LOG_FILE" 2>/dev/null && sudo chown $USER:$USER "$AUDIT_LOG_FILE" 2>/dev/null; then
            : # Success
        else
            # Fallback to local user log if no sudo/permission
            AUDIT_LOG_FILE="$HOME/.k8s_ops.log"
        fi
    fi
}

# Log an action
# Usage: log_action "CATEGORY" "Action Description" "Target (Optional)"
log_action() {
    local category="$1"
    local action="$2"
    local target="${3:-N/A}"
    local user="$USER"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure accessibility on first write
    ensure_audit_log_access

    # Format: Timestamp | User | Category | Action | Target
    local log_entry="$ts | $user | $category | $action | $target"
    
    echo "$log_entry" >> "$AUDIT_LOG_FILE"
}

# Export functions
export -f log_action
export -f ensure_audit_log_access
export AUDIT_LOG_FILE
