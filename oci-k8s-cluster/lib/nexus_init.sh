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
    
    # Retry loop to wait for Nexus to generate the password file
    local max_retries=30
    local count=0
    local password=""
    
    while [ $count -lt $max_retries ]; do
        # Try to get from pod file
        password=$(run_kubectl "exec -n nexus deployment/nexus-deployment -- cat /nexus-data/admin.password" 2>/dev/null | tr -d '\r\n' || true)
        
        if [ -n "$password" ]; then
            break
        fi
        
        echo "Waiting for Nexus to generate admin.password... ($((count+1))/$max_retries)" >&2
        sleep 5
        count=$((count + 1))
    done
    
    if [ -z "$password" ]; then
        echo "Error: Could not retrieve initial admin password (file may not exist after first setup or Nexus is still starting)" >&2
        return 1
    fi
    
    echo "Retrieved initial password (len=${#password})" >&2
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
            # Verify if this password actually works
            local http_code
            http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "admin:$pass" --max-time 5 "$NEXUS_API_BASE/service/rest/v1/blobstores" || echo "000")
            
            if [ "$http_code" = "200" ]; then
                echo "$pass"
                return 0
            else
                echo "Warning: Stored password failed authentication (HTTP $http_code). Checking for new initial password..." >&2
            fi
        fi
    fi
    
    # Try to get initial password from pod
    local initial_pass
    initial_pass=$(nexus_get_initial_password)
    
    if [ -n "$initial_pass" ]; then
        # Verify the initial password too
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "admin:$initial_pass" --max-time 5 "$NEXUS_API_BASE/service/rest/v1/blobstores" || echo "000")
        
        if [ "$http_code" = "200" ]; then
            # Store it with default username "admin"
            # If entry exists (but was wrong), this updates it
            credstore_add "nexus-admin" "admin" "$initial_pass" "Nexus admin account"
            echo "$initial_pass"
            return 0
        else
             echo "Error: Initial password found but failed authentication (HTTP $http_code)" >&2
        fi
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

# Enable NPM Token realm in Nexus
# Must be active for npm login/publish to work
# Usage: nexus_enable_npm_realm
nexus_enable_npm_realm() {
    nexus_check_tunnel || return 1
    local password
    password=$(nexus_get_admin_password)

    echo "Activating NPM Token realm..." >&2

    local response
    response=$(curl -s -w "\n%{http_code}" -u "admin:$password" \
        -X PUT "$NEXUS_API_BASE/service/rest/v1/security/realms/active" \
        -H "Content-Type: application/json" \
        -d '["NexusAuthenticatingRealm","NpmToken"]' 2>&1 || true)

    local http_code
    http_code=$(echo "$response" | tail -n 1)

    if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        echo "✓ NpmToken realm activated" >&2
        return 0
    else
        echo "Error: Failed to activate NpmToken realm (HTTP $http_code)" >&2
        echo "$response" | head -n -1 >&2
        return 1
    fi
}

# Create NPM hosted repository (stores @dnorio/* private packages)
# Usage: nexus_create_npm_hosted <repo_name> <blobstore_name>
nexus_create_npm_hosted() {
    local repo_name="${1:-npm-repo}"
    local blobstore_name="${2:-minio}"

    nexus_check_tunnel || return 1
    local password
    password=$(nexus_get_admin_password)

    echo "Creating NPM hosted repository '$repo_name'..." >&2

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
  "npm": {
    "removeQuarantined": true
  }
}
EOF
)

    local response
    response=$(curl -s -w "\n%{http_code}" -u "admin:$password" \
        -X POST "$NEXUS_API_BASE/service/rest/v1/repositories/npm/hosted" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1 || true)

    local http_code
    http_code=$(echo "$response" | tail -n 1)

    if [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
        echo "✓ NPM hosted repository '$repo_name' created" >&2
        return 0
    elif [ "$http_code" = "400" ] && echo "$response" | grep -qi "already exists"; then
        echo "✓ NPM hosted repository '$repo_name' already exists" >&2
        return 0
    else
        echo "Error: Failed to create NPM hosted repository (HTTP $http_code)" >&2
        echo "$response" | head -n -1 >&2
        return 1
    fi
}

# Create NPM proxy repository (caches registry.npmjs.org)
# Usage: nexus_create_npm_proxy <repo_name> <blobstore_name>
nexus_create_npm_proxy() {
    local repo_name="${1:-npm-proxy}"
    local blobstore_name="${2:-minio}"

    nexus_check_tunnel || return 1
    local password
    password=$(nexus_get_admin_password)

    echo "Creating NPM proxy repository '$repo_name'..." >&2

    local payload
    payload=$(cat <<EOF
{
  "name": "$repo_name",
  "online": true,
  "storage": {
    "blobStoreName": "$blobstore_name",
    "strictContentTypeValidation": true
  },
  "proxy": {
    "remoteUrl": "https://registry.npmjs.org",
    "contentMaxAge": 1440,
    "metadataMaxAge": 1440
  },
  "negativeCache": {
    "enabled": true,
    "timeToLive": 1440
  },
  "httpClient": {
    "blocked": false,
    "autoBlock": true
  },
  "npm": {
    "removeQuarantined": true
  }
}
EOF
)

    local response
    response=$(curl -s -w "\n%{http_code}" -u "admin:$password" \
        -X POST "$NEXUS_API_BASE/service/rest/v1/repositories/npm/proxy" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1 || true)

    local http_code
    http_code=$(echo "$response" | tail -n 1)

    if [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
        echo "✓ NPM proxy repository '$repo_name' created" >&2
        return 0
    elif [ "$http_code" = "400" ] && echo "$response" | grep -qi "already exists"; then
        echo "✓ NPM proxy repository '$repo_name' already exists" >&2
        return 0
    else
        echo "Error: Failed to create NPM proxy repository (HTTP $http_code)" >&2
        echo "$response" | head -n -1 >&2
        return 1
    fi
}

# Create NPM group repository (single endpoint: npm-proxy + npm-repo)
# Usage: nexus_create_npm_group <group_name> <blobstore_name>
nexus_create_npm_group() {
    local group_name="${1:-npm-group}"
    local blobstore_name="${2:-minio}"

    nexus_check_tunnel || return 1
    local password
    password=$(nexus_get_admin_password)

    echo "Creating NPM group repository '$group_name' (npm-proxy + npm-repo)..." >&2

    local payload
    payload=$(cat <<EOF
{
  "name": "$group_name",
  "online": true,
  "storage": {
    "blobStoreName": "$blobstore_name",
    "strictContentTypeValidation": true
  },
  "group": {
    "memberNames": ["npm-proxy", "npm-repo"]
  }
}
EOF
)

    local response
    response=$(curl -s -w "\n%{http_code}" -u "admin:$password" \
        -X POST "$NEXUS_API_BASE/service/rest/v1/repositories/npm/group" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1 || true)

    local http_code
    http_code=$(echo "$response" | tail -n 1)

    if [ "$http_code" = "201" ] || [ "$http_code" = "204" ]; then
        echo "✓ NPM group repository '$group_name' created" >&2
        return 0
    elif [ "$http_code" = "400" ] && echo "$response" | grep -qi "already exists"; then
        echo "✓ NPM group repository '$group_name' already exists" >&2
        return 0
    else
        echo "Error: Failed to create NPM group repository (HTTP $http_code)" >&2
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
    echo "Step 3/8: Creating S3 blob store 'minio'..."
    nexus_create_s3_blobstore "minio" "nexus" "$access_key" "$secret_key"
    echo ""

    # Step 4: Create Docker repository
    echo "Step 4/8: Creating Docker hosted repository..."
    nexus_create_docker_repo "docker-repo" "minio" 18444
    echo ""

    # Step 5: Activate NPM Token realm
    echo "Step 5/8: Activating NPM Token realm..."
    nexus_enable_npm_realm
    echo ""

    # Step 6: Create NPM hosted repository (@dnorio/* private packages)
    echo "Step 6/8: Creating NPM hosted repository..."
    nexus_create_npm_hosted "npm-repo" "minio"
    echo ""

    # Step 7: Create NPM proxy repository (public packages cache)
    echo "Step 7/8: Creating NPM proxy repository..."
    nexus_create_npm_proxy "npm-proxy" "minio"
    echo ""

    # Step 8: Create NPM group repository (single endpoint)
    echo "Step 8/8: Creating NPM group repository..."
    nexus_create_npm_group "npm-group" "minio"
    echo ""

    echo "=== Nexus Initialization Complete ==="
    echo "Blob Store: minio (S3 backed by Minio)"
    echo "Docker Repository: docker-repo (port 18444)"
    echo "NPM Hosted: npm-repo (private @dnorio/* packages)"
    echo "NPM Proxy:  npm-proxy (cache for registry.npmjs.org)"
    echo "NPM Group:  npm-group (single endpoint: registry=http://localhost:8081/repository/npm-group)"
    echo "Admin Password: ${password:0:8}**********"
    echo ""
    echo "Credentials saved to credstore (view with 'View Credentials' menu)"
}

# Reset Nexus (wipe data and restart)
# Usage: nexus_reset
nexus_reset() {
    echo "=== Resetting Nexus ==="
    echo ""
    echo "⚠️  WARNING: This will DELETE all Nexus data (repositories, blob stores, credentials)"
    echo ""
    
    # Step 1: Scale down deployment
    echo "Step 1/5: Scaling down Nexus deployment..."
    run_kubectl "scale deployment/nexus-deployment -n nexus --replicas=0"
    sleep 5
    echo "✓ Deployment scaled down"
    echo ""
    
    # Step 2: Delete PVC
    echo "Step 2/5: Deleting persistent volume claim..."
    run_kubectl "delete pvc nexus-pvc -n nexus --ignore-not-found=true"
    sleep 5
    echo "✓ PVC deleted"
    echo ""
    
    # Step 3: Recreate PVC and Scale up
    echo "Step 3/5: Recreating resources and scaling up..."
    cat "$LIB_DIR/../../components/nexus/nexus-resources.yaml" | run_kubectl "apply -f -"
    run_kubectl "scale deployment/nexus-deployment -n nexus --replicas=1"
    echo "✓ Resources applied and deployment scaled up"
    echo ""
    
    # Step 4: Wait for pod to be ready
    echo "Step 4/5: Waiting for Nexus pod to be ready..."
    local max_wait=120
    local waited=0
    while [ $waited -lt $max_wait ]; do
        local ready=$(run_kubectl "get pods -n nexus -l app=nexus -o jsonpath='{.items[0].status.containerStatuses[0].ready}'" 2>/dev/null || echo "false")
        if [ "$ready" = "true" ]; then
            echo "✓ Nexus pod is ready"
            break
        fi
        echo -n "."
        sleep 5
        waited=$((waited + 5))
    done
    echo ""
    
    if [ $waited -ge $max_wait ]; then
        echo "⚠️  Warning: Nexus pod did not become ready within $max_wait seconds"
        echo "   You may need to check pod status manually"
    fi
    echo ""
    
    # Step 5: Clean up credstore
    echo "Step 5/5: Cleaning up stored credentials..."
    credstore_delete_credential "nexus-admin" 2>/dev/null || true
    echo "✓ Credentials cleared"
    echo ""
    
    echo "=== Nexus Reset Complete ==="
    echo ""
    echo "Next steps:"
    echo "1. Run 'Initialize Nexus' to set up Nexus with fresh admin.password"
    echo "2. Credentials will be automatically stored in credstore"
}


# Export functions if sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f nexus_check_tunnel nexus_get_initial_password nexus_get_admin_password nexus_change_password \
        nexus_create_s3_blobstore nexus_create_docker_repo \
        nexus_enable_npm_realm nexus_create_npm_hosted nexus_create_npm_proxy nexus_create_npm_group \
        nexus_initialize nexus_reset
fi
