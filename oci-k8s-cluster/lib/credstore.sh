#!/usr/bin/env bash
# Credential Store Manager v2 for K8s Ops
# Stores credentials with name/username/password/description
# Username and password are individually encrypted

set -eo pipefail

CREDSTORE_DIR="$HOME/.local/share/k8s_ops"
CREDSTORE_FILE="$CREDSTORE_DIR/credentials.json"
CREDSTORE_VERSION=2

# Simple field encryption/decryption using openssl
encrypt_field() {
    local value="$1"
    printf '%s' "$value" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass "pass:k8s-ops-$(whoami)" 2>/dev/null
}

decrypt_field() {
    local encrypted="$1"
    
    if [ -z "$encrypted" ]; then
        echo ""
        return 1
    fi
    
    local decrypted
    decrypted=$(echo "$encrypted" | openssl enc -aes-256-cbc -d -a -pbkdf2 -pass "pass:k8s-ops-$(whoami)" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        # Silently return empty on error
        echo ""
        return 1
    fi
    
    printf '%s' "$decrypted"
}

# Initialize credential store
credstore_init() {
    mkdir -p "$CREDSTORE_DIR"
    chmod 700 "$CREDSTORE_DIR"
    
    if [ ! -f "$CREDSTORE_FILE" ]; then
        echo '{"version": 2, "credentials": []}' > "$CREDSTORE_FILE"
        chmod 600 "$CREDSTORE_FILE"
    else
        # Check version and migrate if needed
        local version
        version=$(jq -r '.version // 1' "$CREDSTORE_FILE" 2>/dev/null || echo "1")
        
        if [ "$version" = "1" ] || [ "$version" = "null" ]; then
            credstore_migrate_v1_to_v2
        fi
    fi
}

# Migrate from v1 (hierarchical) to v2 (flat with encryption)
credstore_migrate_v1_to_v2() {
    echo "Migrating credential store from v1 to v2..." >&2
    
    local backup_file="$CREDSTORE_FILE.v1.backup"
    cp "$CREDSTORE_FILE" "$backup_file"
    
    # Build v2 structure
    local new_creds='{"version": 2, "credentials": []}'
    
    # Migrate minio credentials
    local minio_user=$(jq -r '.minio.root_user // empty' "$CREDSTORE_FILE" 2>/dev/null)
    local minio_pass=$(jq -r '.minio.root_password // empty' "$CREDSTORE_FILE" 2>/dev/null)
    if [ -n "$minio_user" ]; then
        local enc_user=$(encrypt_field "$minio_user")
        local enc_pass=$(encrypt_field "$minio_pass")
        new_creds=$(echo "$new_creds" | jq ".credentials += [{\"name\": \"minio-root\", \"username\": \"$enc_user\", \"password\": \"$enc_pass\", \"description\": \"Minio root account\"}]")
    fi
    
    local minio_access=$(jq -r '.minio.nexus_access_key // empty' "$CREDSTORE_FILE" 2>/dev/null)
    local minio_secret=$(jq -r '.minio.nexus_secret_key // empty' "$CREDSTORE_FILE" 2>/dev/null)
    if [ -n "$minio_access" ]; then
        local enc_access=$(encrypt_field "$minio_access")
        local enc_secret=$(encrypt_field "$minio_secret")
        new_creds=$(echo "$new_creds" | jq ".credentials += [{\"name\": \"minio-s3-nexus\", \"username\": \"$enc_access\", \"password\": \"$enc_secret\", \"description\": \"S3 credentials for Nexus blob storage\"}]")
    fi
    
    # Migrate nexus credentials
    local nexus_pass=$(jq -r '.nexus.admin_password // empty' "$CREDSTORE_FILE" 2>/dev/null)
    if [ -n "$nexus_pass" ]; then
        local enc_user=$(encrypt_field "admin")
        local enc_pass=$(encrypt_field "$nexus_pass")
        new_creds=$(echo "$new_creds" | jq ".credentials += [{\"name\": \"nexus-admin\", \"username\": \"$enc_user\", \"password\": \"$enc_pass\", \"description\": \"Nexus admin account\"}]")
    fi
    
    echo "$new_creds" > "$CREDSTORE_FILE"
    chmod 600 "$CREDSTORE_FILE"
    
    echo "✓ Migration complete. Backup saved to $backup_file" >&2
}

# Add a credential
# Usage: credstore_add <name> <username> <password> <description>
credstore_add() {
    local name="$1"
    local username="$2"
    local password="$3"
    local description="$4"
    
    credstore_init
    
    # Check if credential with this name already exists
    local exists
    exists=$(jq --arg name "$name" '.credentials[] | select(.name == $name) | .name' "$CREDSTORE_FILE" 2>/dev/null || true)
    
    if [ -n "$exists" ]; then
        # Update existing credential instead of failing
        credstore_update "$name" "username" "$username"
        credstore_update "$name" "password" "$password"
        credstore_update "$name" "description" "$description"
        return 0
    fi
    
    # Encrypt sensitive fields
    local enc_username=$(encrypt_field "$username")
    local enc_password=$(encrypt_field "$password")
    
    # Add to credentials array
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg name "$name" \
       --arg user "$enc_username" \
       --arg pass "$enc_password" \
       --arg desc "$description" \
       '.credentials += [{"name": $name, "username": $user, "password": $pass, "description": $desc}]' \
       "$CREDSTORE_FILE" > "$tmp_file"
    mv "$tmp_file" "$CREDSTORE_FILE"
    chmod 600 "$CREDSTORE_FILE"
}

# Get a credential (decrypted)
# Usage: credstore_get_credential <name>
# Returns: JSON object with decrypted username/password
credstore_get_credential() {
    local name="$1"
    
    credstore_init
    
    local cred_json
    cred_json=$(jq --arg name "$name" '.credentials[] | select(.name == $name)' "$CREDSTORE_FILE" 2>/dev/null || echo "{}")
    
    if [ -z "$cred_json" ] || [ "$cred_json" = "{}" ]; then
        return 1
    fi
    
    # Decrypt fields
    local enc_user=$(echo "$cred_json" | jq -r '.username')
    local enc_pass=$(echo "$cred_json" | jq -r '.password')
    local desc=$(echo "$cred_json" | jq -r '.description')
    
    local dec_user=$(decrypt_field "$enc_user")
    local dec_pass=$(decrypt_field "$enc_pass")
    
    # Use jq to safely construct JSON
    jq -n \
      --arg name "$name" \
      --arg user "$dec_user" \
      --arg pass "$dec_pass" \
      --arg desc "$desc" \
      '{name: $name, username: $user, password: $pass, description: $desc}'
}

# Update a credential field
# Usage: credstore_update <name> <field> <value>
# field: username, password, or description
credstore_update() {
    local name="$1"
    local field="$2"
    local value="$3"
    
    credstore_init
    
    local tmp_file
    tmp_file=$(mktemp)
    
    if [ "$field" = "username" ] || [ "$field" = "password" ]; then
        # Encrypt sensitive fields
        local enc_value=$(encrypt_field "$value")
        jq --arg name "$name" --arg field "$field" --arg val "$enc_value" \
           '(.credentials[] | select(.name == $name) | .[$field]) = $val' \
           "$CREDSTORE_FILE" > "$tmp_file"
    else
        # Description is not encrypted
        jq --arg name "$name" --arg field "$field" --arg val "$value" \
           '(.credentials[] | select(.name == $name) | .[$field]) = $val' \
           "$CREDSTORE_FILE" > "$tmp_file"
    fi
    
    mv "$tmp_file" "$CREDSTORE_FILE"
    chmod 600 "$CREDSTORE_FILE"
}

# Delete a credential
# Usage: credstore_delete_credential <name>
credstore_delete_credential() {
    local name="$1"
    
    credstore_init
    
    local tmp_file
    tmp_file=$(mktemp)
    jq --arg name "$name" '.credentials = [.credentials[] | select(.name != $name)]' \
       "$CREDSTORE_FILE" > "$tmp_file"
    mv "$tmp_file" "$CREDSTORE_FILE"
    chmod 600 "$CREDSTORE_FILE"
}

# List credential names and descriptions (for menu display)
# Returns: name - description (one per line)
credstore_list_names() {
    credstore_init
    
    jq -r '.credentials[] | .name + " - " + .description' "$CREDSTORE_FILE" 2>/dev/null || true
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f credstore_init credstore_add credstore_get_credential credstore_update credstore_delete_credential credstore_list_names credstore_migrate_v1_to_v2
fi
