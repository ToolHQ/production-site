#!/usr/bin/env bash
# Preferences Manager for K8s Ops TUI
# Stores user preferences for language, menu order, and port forwarding

set -eo pipefail

PREFS_DIR="$HOME/.local/share/k8s_ops"
PREFS_FILE="$PREFS_DIR/preferences.json"
PREFS_VERSION=1

# Default preferences
DEFAULT_LANGUAGE="en"
DEFAULT_MENU_ORDER='["k9s","port_forward","service_config","credentials","components","dashboard","namespace","pod","all_pods","nodes","update","maintenance","preferences","exit"]'
DEFAULT_AUTO_PORTS='[]'

# Initialize preferences store
prefs_init() {
    mkdir -p "$PREFS_DIR"
    chmod 700 "$PREFS_DIR"
    
    if [ ! -f "$PREFS_FILE" ]; then
        cat > "$PREFS_FILE" <<EOF
{
  "version": $PREFS_VERSION,
  "language": "$DEFAULT_LANGUAGE",
  "menu_order": $DEFAULT_MENU_ORDER,
  "auto_ports": $DEFAULT_AUTO_PORTS
}
EOF
        chmod 600 "$PREFS_FILE"
    fi
}

# Get a preference value
# Usage: prefs_get <key>
prefs_get() {
    local key="$1"
    
    prefs_init
    
    jq -r ".$key // empty" "$PREFS_FILE" 2>/dev/null || echo ""
}

# Set a preference value
# Usage: prefs_set <key> <value>
prefs_set() {
    local key="$1"
    local value="$2"
    
    prefs_init
    
    local tmp_file
    tmp_file=$(mktemp)
    
    # Handle JSON values (arrays/objects) vs strings
    if [[ "$value" =~ ^\[.*\]$ ]] || [[ "$value" =~ ^\{.*\}$ ]]; then
        # Value is already JSON
        jq --arg key "$key" --argjson val "$value" '.[$key] = $val' "$PREFS_FILE" > "$tmp_file"
    else
        # Value is a string
        jq --arg key "$key" --arg val "$value" '.[$key] = $val' "$PREFS_FILE" > "$tmp_file"
    fi
    
    mv "$tmp_file" "$PREFS_FILE"
    chmod 600 "$PREFS_FILE"
}

# Get current language
prefs_get_language() {
    local lang
    lang=$(prefs_get "language")
    echo "${lang:-$DEFAULT_LANGUAGE}"
}

# Set language
# Usage: prefs_set_language <en|pt_BR>
prefs_set_language() {
    local lang="$1"
    prefs_set "language" "$lang"
}

# Get menu order
prefs_get_menu_order() {
    local order
    order=$(prefs_get "menu_order")
    if [ -z "$order" ] || [ "$order" = "null" ]; then
        echo "$DEFAULT_MENU_ORDER"
    else
        echo "$order"
    fi
}

# Set menu order
# Usage: prefs_set_menu_order <json_array>
prefs_set_menu_order() {
    local order="$1"
    prefs_set "menu_order" "$order"
}

# Get auto port forwarding list
prefs_get_auto_ports() {
    local ports
    ports=$(prefs_get "auto_ports")
    if [ -z "$ports" ] || [ "$ports" = "null" ]; then
        echo "$DEFAULT_AUTO_PORTS"
    else
        echo "$ports"
    fi
}

# Set auto port forwarding list
# Usage: prefs_set_auto_ports <json_array>
# Example: prefs_set_auto_ports '[{"namespace":"minio","service":"minio-service","port":"9000"},{"namespace":"nexus","service":"nexus-service","port":"8081"}]'
prefs_set_auto_ports() {
    local ports="$1"
    prefs_set "auto_ports" "$ports"
}

# Add a port to auto forwarding list
# Usage: prefs_add_auto_port <namespace> <service> <port>
prefs_add_auto_port() {
    local namespace="$1"
    local service="$2"
    local port="$3"
    
    prefs_init
    
    local current_ports
    current_ports=$(prefs_get_auto_ports)
    
    # Check if port already exists
    local exists
    exists=$(echo "$current_ports" | jq --arg ns "$namespace" --arg svc "$service" --arg p "$port" \
        'map(select(.namespace == $ns and .service == $svc and .port == $p)) | length')
    
    if [ "$exists" -gt 0 ]; then
        return 0
    fi
    
    # Add new port
    local new_ports
    new_ports=$(echo "$current_ports" | jq --arg ns "$namespace" --arg svc "$service" --arg p "$port" \
        '. += [{"namespace": $ns, "service": $svc, "port": $p}]')
    
    prefs_set_auto_ports "$new_ports"
}

# Remove a port from auto forwarding list
# Usage: prefs_remove_auto_port <namespace> <service> <port>
prefs_remove_auto_port() {
    local namespace="$1"
    local service="$2"
    local port="$3"
    
    prefs_init
    
    local current_ports
    current_ports=$(prefs_get_auto_ports)
    
    local new_ports
    new_ports=$(echo "$current_ports" | jq --arg ns "$namespace" --arg svc "$service" --arg p "$port" \
        'map(select(.namespace != $ns or .service != $svc or .port != $p))')
    
    prefs_set_auto_ports "$new_ports"
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f prefs_init prefs_get prefs_set prefs_get_language prefs_set_language
    export -f prefs_get_menu_order prefs_set_menu_order prefs_get_auto_ports prefs_set_auto_ports
    export -f prefs_add_auto_port prefs_remove_auto_port
fi
