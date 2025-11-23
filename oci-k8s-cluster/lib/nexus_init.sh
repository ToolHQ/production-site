#!/usr/bin/env bash
# Nexus Automation Script
# Handles admin password retrieval, S3 blob store creation, and Docker repository setup

set -eo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/credstore.sh"
source "$LIB_DIR/../common.sh"

NEXUS_API_BASE="http://localhost:8081"

# Ensure tunnel to Nexus is active
# Returns 0 if tunnel exists, 1 otherwise
nexus_check_tunnel() {
    if lsof -i :8081 >/dev/null 2>&1; then
        return 0
    else
        echo "Error: No tunnel to Nexus on port 8081" >&2
        echo "Please start tunnel via 'Access & Port Forwarding' menu" >&2
        return 1
    fi
}

# Get initial admin password from Nexus pod
# Usage: nexus_get_initial_password
nexus_get_initial_password() {
    echo "Fetching initial Nexus admin password..." >&2
    
    # Try to get from pod file
    local password
    password=$(run_kubectl "exec -n nexus deployment/nexus -- cat /nexus-data/admin.password" 2>/dev/null | tr -d '\r' || true)
    
    if [ -z "$password" ]; then
        echo "Error: Could not retrieve initial admin password (file may not exist after first setup)" >&2
        return 1
    fi
    
    echo "$password"
}

# Get admin password (tries credstore first, then initial password file)
# Usage: nexus_get_admin_password
nexus_get_admin_password() {
    local cred_json
    cred_json=$(credstore_get_credential "nexus-admin" 2>/dev/null || echo "{}")
    
    if [ "$cred_json" != "{}" ]; then
        local pass=$(echo "$cred_json" | jq -r '.password')
        if [ -n "$pass" ]; then
            echo "$pass"
            return 0
        fi
    fi
    
    # Try to get initial password
    local initial_pass
    initial_pass=$(nexus_get_initial_password 2>&1)
    
    if [ -n "$initial_pass" ]; then
        # Store it with default username "admin"
        credstore_add "nexus-admin" "admin" "$initial_pass" "Nexus admin account"
        echo "$initial_pass"
        return 0
    fi
    
    return 1
}

# Change admin password
# Usage: nexus_change_password <new_password>
nexus_change_password() {
    local new_password="$1"
    
    if [ -z "$new_password" ]; then
        echo "Error: new_password required" >&2
        return 1
    fi
    
    nexus_check_tunnel || return 1
    
    local current_password
    current_password=$(nexus_get_admin_password)
    
    if [ -z "$current_password" ]; then
        echo "Error: Could not retrieve current admin password" >&2
        return 1
    fi
    
    echo "Changing Nexus admin password..." >&2
    
    # Use Nexus REST API to change password
    local response
    response=$(curl -s -w "\n%{http_code}" -u "admin:$current_password" \
        -X PUT "$NEXUS_API_BASE/service/rest/v1/security/users/admin/change-password" \
        -H "Content-Type: text/plain" \
        -d "$new_password" 2>&1 || true)
    
    local http_code
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        credstore_update "nexus-admin" "password" "$new_password"
        echo "✓ Password changed successfully" >&2
        return 0
    else
        echo "Error: Failed to change password (HTTP $http_code)" >&2
        echo "$response" >&2
        return 1
    fi
}

# Create S3 blob store using Minio
# Usage: nexus_create_s3_blobstore <name> <bucket> <access_key> <secret_key>
nexus_create_s3_blobstore() {
    local name="$1"
    local bucket="$2"
    local access_key="$3"
    local secret_key="$4"
    
    nexus_check_tunnel || return 1
    
    local password
    password=$(nexus_get_admin_password)
    
    echo "Creating S3 blob store '$name'..." >&2
    
    # Minio endpoint (ClusterIP service)
    local minio_endpoint="http://minio-service.minio.svc.cluster.local:9000"
    
    # Build JSON payload based on user's config images
    local payload
    payload=$(cat <<EOF
{
  "name": "$name",
  "type": "S3",
  "bucketConfiguration": {
    "bucket": {
      "name": "$bucket",
      "region": "us-east-1",
      "prefix": "",
      "expiration": -1
    },
    "bucketSecurity": {
      "accessKeyId": "$access_key",
      "secretAccessKey": "$secret_key",
      "role": "",
      "sessionToken": ""
    },
    "encryption": null,
    "advancedBucketConnection": {
      "endpoint": "$minio_endpoint",
      "signerType": "",
      "forcePathStyle": true,
      "maxConnectionPoolSize": null
    }
  },
  "softQuota": null
}
EOF
)
    
    local response
    response=$(curl -s -w "\n%{http_code}" -u "admin:$password" \
        -X POST "$NEXUS_API_BASE/service/rest/v1/blobstores/s3" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1 || true)
    
    local http_code
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
        echo "✓ S3 blob store '$name' created successfully" >&2
        return 0
    elif [ "$http_code" = "400" ] && echo "$response" | grep -qi "already exists"; then
        echo "✓ S3 blob store '$name' already exists" >&2
        return 0
    else
        echo "Error: Failed to create S3 blob store (HTTP $http_code)" >&2
        echo "$response" | head -n -1 >&2
        return 1
    fi
}

# Create Docker hosted repository
# Usage: nexus_create_docker_repo <repo_name> <blobstore_name> <http_port>
nexus_create_docker_repo() {
    local repo_name="$1"
    local blobstore_name="$2"
    local http_port="${3:-18444}"
    
    nexus_check_tunnel || return 1
    
    local password
    password=$(nexus_get_admin_password)
    
    echo "Creating Docker hosted repository '$repo_name'..." >&2
    
    # Build JSON payload
    local payload
    payload=$(cat <<EOF
{
  "name": "$repo_name",
  "online": true,
  "storage": {
    "blobStoreName": "$blobstore_name",
    "strictContentTypeValidation": true,
    "writePolicy": "ALLOW"
  },
  "cleanup": null,
  "component": {
    "proprietaryComponents": false
  },
  "docker": {
    "v1Enabled": false,
    "forceBasicAuth": true,
    "httpPort": $http_port,
    "httpsPort": null,
    "subdomain": null
  }
}
EOF
)
    
    local response
    response=$(curl -s -w "\n%{http_code}" -u "admin:$password" \
        -X POST "$NEXUS_API_BASE/service/rest/v1/repositories/docker/hosted" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1 || true)
    
    local http_code
    http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
        echo "✓ Docker repository '$repo_name' created successfully" >&2
        return 0
    elif [ "$http_code" = "400" ] && echo "$response" | grep -qi "already exists"; then
        echo "✓ Docker repository '$repo_name' already exists" >&2
        return 0
    else
        echo "Error: Failed to create Docker repository (HTTP $http_code)" >&2
        echo "$response" | head -n -1 >&2
        return 1
    fi
}

# Full initialization: password + S3 blob store + Docker repo
# Usage: nexus_initialize
nexus_initialize() {
    echo "=== Initializing Nexus ==="
    echo ""
    
    # Step 1: Get admin password
    echo "Step 1/3: Retrieving admin password..."
    local password
    password=$(nexus_get_admin_password)
    if [ -z "$password" ]; then
        echo "✗ Failed to retrieve admin password" >&2
        return 1
    fi
    echo "✓ Admin password retrieved"
    echo ""
    
    # Step 2: Get Minio credentials from credstore
    echo "Step 2/3: Fetching Minio S3 credentials..."
    local access_key
    local secret_key
    
    local minio_cred_json
    minio_cred_json=$(credstore_get_credential "minio-s3-nexus" 2>/dev/null || echo "{}")
    
    if [ "$minio_cred_json" = "{}" ]; then
        echo "✗ Minio credentials not found in credstore" >&2
        echo "Please run 'Initialize Minio' first" >&2
        return 1
    fi
    
    access_key=$(echo "$minio_cred_json" | jq -r '.username')
    secret_key=$(echo "$minio_cred_json" | jq -r '.password')
    
    if [ -z "$access_key" ] || [ -z "$secret_key" ]; then
        echo "✗ Minio credentials found but empty (likely due to encryption change)" >&2
        echo "Please run 'Initialize Minio' again to fix this" >&2
        return 1
    fi
    echo "✓ Minio credentials retrieved"
    echo ""
    
    # Step 3: Create S3 blob store
    echo "Step 3/4: Creating S3 blob store 'minio'..."
    nexus_create_s3_blobstore "minio" "nexus" "$access_key" "$secret_key"
    echo ""
    
    # Step 4: Create Docker repository
    echo "Step 4/4: Creating Docker hosted repository..."
    nexus_create_docker_repo "docker-repo" "minio" 18444
    echo ""
    
    echo "=== Nexus Initialization Complete ==="
    echo "Blob Store: minio (S3 backed by Minio)"
    echo "Docker Repository: docker-repo (port 18444)"
    echo "Admin Password: ${password:0:8}**********"
    echo ""
    echo "Credentials saved to credstore (view with 'View Credentials' menu)"
}

# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f nexus_check_tunnel nexus_get_initial_password nexus_get_admin_password nexus_change_password nexus_create_s3_blobstore nexus_create_docker_repo nexus_initialize
fi
