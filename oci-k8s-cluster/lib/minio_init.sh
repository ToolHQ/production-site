#!/usr/bin/env bash
# Minio Automation Script - Using netshoot + Minio Admin API
# Fully automated bucket and access key creation

set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/credstore.sh"
source "$LIB_DIR/../common.sh"

# Get Minio root credentials from Kubernetes Secret
minio_get_credentials() {
    # Try to get from credstore first
    local cred_json
    cred_json=$(credstore_get_credential "minio-root" 2>/dev/null || echo "{}")
    
    if [ "$cred_json" != "{}" ]; then
        local user=$(echo "$cred_json" | jq -r '.username')
        local pass=$(echo "$cred_json" | jq -r '.password')
        if [ -n "$user" ] && [ -n "$pass" ]; then
            echo "$user|$pass"
            return 0
        fi
    fi
    
    echo "Fetching Minio root credentials from Kubernetes Secret..." >&2
    
    # Get credentials from minio-secret
    local minio_user
    local minio_pass
    
    minio_user=$(run_kubectl "get secret -n minio minio-secret -o jsonpath='{.data.MINIO_ROOT_USER}'" 2>/dev/null)
    if [ -z "$minio_user" ]; then
        echo "Error: Failed to retrieve MINIO_ROOT_USER from secret" >&2
        return 1
    fi
    
    minio_pass=$(run_kubectl "get secret -n minio minio-secret -o jsonpath='{.data.MINIO_ROOT_PASSWORD}'" 2>/dev/null)
    if [ -z "$minio_pass" ]; then
        echo "Error: Failed to retrieve MINIO_ROOT_PASSWORD from secret" >&2
        return 1
    fi
    
    # Decode base64
    minio_user=$(echo "$minio_user" | base64 -d 2>/dev/null | tr -d '\r\n')
    minio_pass=$(echo "$minio_pass" | base64 -d 2>/dev/null | tr -d '\r\n')
    
    if [ -z "$minio_user" ] || [ -z "$minio_pass" ]; then
        echo "Error: Failed to decode Minio credentials (base64 decode failed)" >&2
        return 1
    fi
    
    echo "Retrieved: user='$minio_user' (len=${#minio_user})" >&2
    
    # Store in credstore
    if ! credstore_add "minio-root" "$minio_user" "$minio_pass" "Minio root account for admin access" 2>&1; then
        echo "Warning: Failed to store credentials in credstore" >&2
    fi
    
    echo "$minio_user|$minio_pass"
}

# Helper: Run mc command via temporary pod
run_mc() {
    local cmd="$1"
    echo "Running mc command: $cmd" >&2
    
    # Run a single-shot mc pod
    # We mount a config volume or pass credentials via env
    local creds
    creds=$(minio_get_credentials)
    local root_user="${creds%%|*}"
    local root_pass="${creds##*|}"
    
    local pod_name="minio-init-$(date +%s)"
    
    # Create a pod that configures alias and runs command
    # We use the official mc image
    local script="mc alias set myminio http://minio-service.minio.svc.cluster.local:9000 $root_user $root_pass && $cmd"
    
    run_kubectl "run $pod_name --rm -i --image=minio/mc --restart=Never --command -- /bin/sh -c '$script'" 2>&1
}

# Create bucket using mc
minio_create_bucket() {
    local bucket_name="$1"
    
    if [ -z "$bucket_name" ]; then
        echo "Error: bucket_name required" >&2
        return 1
    fi
    
    echo "Creating bucket '$bucket_name' in Minio..." >&2
    
    # mc mb --ignore-existing myminio/<bucket>
    if run_mc "mc mb --ignore-existing myminio/$bucket_name"; then
        echo "✓ Bucket '$bucket_name' is ready" >&2
        return 0
    else
        echo "Error: Failed to create bucket" >&2
        return 1
    fi
}

# Create service account (access key) using mc
minio_create_access_key() {
    local description="${1:-nexus-service}"
    
    echo "Creating Minio access key for '$description'..." >&2
    
    # Check if we already have stored keys
    local cred_json
    cred_json=$(credstore_get_credential "minio-s3-nexus" 2>/dev/null || echo "{}")
    
    if [ "$cred_json" != "{}" ]; then
        local access_key=$(echo "$cred_json" | jq -r '.username')
        local secret_key=$(echo "$cred_json" | jq -r '.password')
        
        # Only use if values are valid (non-empty)
        if [ -n "$access_key" ] && [ -n "$secret_key" ]; then
            # Verify if key actually exists in Minio (in case of data wipe)
            if run_mc "mc admin user svcacct info myminio $access_key >/dev/null 2>&1"; then
                echo "Using existing access key from credstore (verified in Minio)" >&2
                echo "$access_key|$secret_key"
                return 0
            else
                echo "Access key found in credstore but missing in Minio (likely wiped). Recreating..." >&2
            fi
        else
            echo "Found existing entry but values are empty. Recreating..." >&2
        fi
    fi
    
    # Generate random keys
    # Generate random keys (max 20 chars for access key)
    local access_key="nexus-$(openssl rand -hex 4)"
    local secret_key="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-40)"
    
    # mc admin user svcacct add myminio <root_user> --access-key <key> --secret-key <secret>
    # Note: We need to create it for the root user
    local creds
    creds=$(minio_get_credentials)
    local root_user="${creds%%|*}"
    
    local output
    if output=$(run_mc "mc admin user svcacct add myminio $root_user --access-key $access_key --secret-key $secret_key --name \"$description\""); then
        # Store in credstore
        credstore_add "minio-s3-nexus" "$access_key" "$secret_key" "S3 credentials for Nexus blob storage"
        echo "✓ Access key stored in credstore" >&2
        echo "$access_key|$secret_key"
        return 0
    else
        echo "Error: Failed to create access key" >&2
        echo "Output: $output" >&2
        return 1
    fi
}

# Full initialization
minio_initialize() {
    local bucket_name="${1:-nexus}"
    
    echo "=== Initializing Minio ==="
    echo ""
    
    # Step 1: Get/store credentials
    echo "Step 1/3: Fetching root credentials..."
    local creds
    creds=$(minio_get_credentials)
    local root_user="${creds%%|*}"
    local root_pass="${creds##*|}"
    echo "✓ Root credentials stored"
    echo ""
    
    # Step 2: Create bucket
    echo "Step 2/3: Creating bucket '$bucket_name'..."
    minio_create_bucket "$bucket_name"
    echo "✓ Bucket ready"
    echo ""
    
    # Step 3: Create access key
    echo "Step 3/3: Creating access key for Nexus..."
    local keys
    keys=$(minio_create_access_key "nexus-docker")
    local access_key="${keys%%|*}"
    local secret_key="${keys##*|}"
    echo "✓ Access key created"
    echo ""
    
    echo "=== Minio Initialization Complete ==="
    echo "Bucket: $bucket_name"
    echo "Access Key ID: $access_key"
    echo "Secret Key: ${secret_key:0:10}**********"
    echo ""
    echo "Credentials saved to credstore (view with 'View Credentials' menu)"
    echo ""
    echo -e "${YELLOW}Note: If Nexus initialization fails, you may need to create the access key manually via Minio UI${NC}"
    echo -e "${YELLOW}Root credentials are available in 'View Credentials' menu${NC}"
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f minio_get_credentials minio_create_bucket minio_create_access_key minio_initialize run_mc
fi
