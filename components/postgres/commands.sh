#!/bin/bash
set -euo pipefail

# PostgreSQL Deployment Script
# Tested in 2024-03-24
# Updated: 2025-11-08 - Added Longhorn support and improved error handling
# Reference: https://www.digitalocean.com/community/tutorials/how-to-deploy-postgres-to-kubernetes-cluster

echo "🐘 Starting PostgreSQL deployment..."

# === SMART BUILD LOGIC ===
HASH_FILE=".last_build_hash"
FILES_TO_MONITOR="Dockerfile postgresql.conf pg_upgrade.sh run_upgrade.sh upgrade.yaml"

# Calculate current hash (MD5 of combined file content)
# We handle missing files gracefully by checking existence
CURRENT_HASH=""
for f in $FILES_TO_MONITOR; do
    if [ -f "$f" ]; then
        CURRENT_HASH="${CURRENT_HASH}$(md5sum "$f" | awk '{print $1}')"
    fi
done
CURRENT_HASH=$(echo "$CURRENT_HASH" | md5sum | awk '{print $1}')

# Check if build is needed
BUILD_NEEDED=false
if [ ! -f "$HASH_FILE" ]; then
    echo "🆕 No previous build detected. Initializing Smart Build..."
    BUILD_NEEDED=true
else
    LAST_HASH=$(cat "$HASH_FILE")
    if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
         echo "♻️  Changes detected in configuration/Dockerfile."
         BUILD_NEEDED=true
    else
         echo "✅ No changes detected. Skipping build."
    fi
fi

# Override force build if build.sh missing
if [ ! -f ./build.sh ]; then
    echo "⚠️  build.sh not found. Cannot build. Using public/existing image."
    BUILD_NEEDED=false
fi

if [ "$BUILD_NEEDED" == "true" ]; then
    echo "📦 Starting Smart Build..."
    
    # FIX: Ensure registry.local resolves to ClusterIP, not 127.0.0.1
    # We discovered that /etc/hosts on master points registry.local to 127.0.0.1 but no tunnel exists.
    # We need to find the ClusterIP of the Nexus service and update/add host entry.
    
    echo "🔧 Improving Registry Connectivity..."
    # We need to map registry.local to the Node IP (where NodePort 31444 is listening).
    # Using ClusterIP would fail because ClusterIP listens on 18444, but our tag uses 31444.
    
    # Get Master IP (Internal)
    # We assume standard 10.0.1.100 or detect it
    NODE_IP=$(hostname -I | awk '{print $1}')
    # Or hardcode if we are sure
    NODE_IP="10.0.1.100" # Master Private IP
    
    if [ -n "$NODE_IP" ]; then
        echo "   Using Node IP for Registry: $NODE_IP"
        # Remove old entry if exists (rudimentary)
        sudo sed -i '/registry.local/d' /etc/hosts || true
        # Add new entry
        echo "$NODE_IP registry.local" | sudo tee -a /etc/hosts >/dev/null
        echo "   Updated /etc/hosts: registry.local -> $NODE_IP"
        
        # FIX: Restart BuildKit to flush DNS cache (crucial because it caches 127.0.0.1)
        echo "♻️  Restarting BuildKit service to flush DNS cache..."
        systemctl --user restart buildkit.service
        
        # Wait for socket
        sleep 5
        
        # Verify hosts
        # grep "registry.local" /etc/hosts
    else
        echo "⚠️  Could not find Node IP."
    fi
    
    # Enable Insecure Registry (HTTP) for BuildKit
    export REGISTRY_INSECURE=true

    # Extract Postgres version from Dockerfile
    # Tag logic: registry.../postgres:<BaseVersion>-<Hash>
    # If FROM is postgres:18.0-alpine3.22 -> BaseVersion = 18.0-alpine3.22
    # If FROM is postgres (no tag) -> BaseVersion = latest
    PG_VERSION=$(grep '^FROM' Dockerfile | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')
    PG_VERSION=${PG_VERSION:-latest}
    echo "ℹ️  Detected Postgres Version from Dockerfile: $PG_VERSION"

    # Generate Version Tag: <Version>-<short_hash>
    # We use the first 7 chars of the content hash as the version suffix
    VERSION_SUFFIX="${CURRENT_HASH:0:7}"
    BASE_IMAGE="registry.local:31444/repository/docker-repo/postgres"
    NEW_TAG="${BASE_IMAGE}:${PG_VERSION}-${VERSION_SUFFIX}"
    
    echo "🏷️  New Image Tag: $NEW_TAG"
    
    # Run Build
    if ./build.sh "$NEW_TAG"; then
        echo "✅ Build & Push Successful."
        
        # Save Hash
        echo "$CURRENT_HASH" > "$HASH_FILE"
        
        # Update YAML with new tag
        echo "📝 Updating postgres-resources.yaml..."
        # Use sed to replace the image line. We match the image: registry.local... line
        # We look for 'image: registry.local.*' and replace it with new tag
        sed -i "s|image: registry.local:31444/.*|image: $NEW_TAG|g" postgres-resources.yaml
        
        echo "✅ YAML Updated."
    else
        echo "❌ Build Failed! Aborting deployment."
        exit 1
    fi
else
    echo "⏭️  Using existing image defined in YAML."
    
    # FIX: Even if we skip the build, we must ensure the YAML uses the hashed tag.
    # Why? Because deploy_components.sh overwrites the remote YAML with the local (default) one.
    
    # Reconstruct version (for consistency checks or ensuring YAML is correct)
    PG_VERSION=$(grep '^FROM' Dockerfile | head -n 1 | awk -F':' '{print $2}' | tr -d ' \r\n')
    PG_VERSION=${PG_VERSION:-latest}
    
    VERSION_SUFFIX="${CURRENT_HASH:0:7}"
    BASE_IMAGE="registry.local:31444/repository/docker-repo/postgres"
    NEW_TAG="${BASE_IMAGE}:${PG_VERSION}-${VERSION_SUFFIX}"

    echo "📝 Updating postgres-resources.yaml to match hash (Tag: ${VERSION_SUFFIX})..."
    sed -i "s|image: registry.local:31444/.*|image: $NEW_TAG|g" postgres-resources.yaml
    echo "✅ YAML Updated."
fi
# =========================

# Verify Longhorn storage class is available
echo "🔍 Verifying Longhorn storage class..."
if ! kubectl get storageclass longhorn >/dev/null 2>&1; then
    echo "⚠️  Warning: Longhorn storage class not found. The deployment may fail."
    echo "   Available storage classes:"
    kubectl get storageclass
    read -p "   Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Deployment cancelled."
        exit 1
    fi
fi

# Check for existing deployment and handle Multi-Attach errors
echo "🔍 Checking for existing PostgreSQL deployment..."
if kubectl -n postgres get deployment postgres-deployment >/dev/null 2>&1; then
    echo "⚠️  Existing PostgreSQL deployment found."
    
    # Check for stuck pods or volume attachment issues
    stuck_pods=$(kubectl -n postgres get pods -l app=postgres --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | grep -c "postgres" 2>/dev/null || echo "0")
    stuck_pods=$(echo "$stuck_pods" | tr -d '\n\r' | grep -o '[0-9]*' | head -1)
    stuck_pods=${stuck_pods:-0}
    
    if [ "$stuck_pods" -gt 0 ]; then
        echo "⚠️  Found $stuck_pods stuck pod(s). This may cause Multi-Attach errors."
        echo "   Cleaning up stuck pods..."
        
        # Force delete stuck pods
        kubectl -n postgres delete pods -l app=postgres --force --grace-period=0 2>/dev/null || true
        
        # Wait for volume detachment
        echo "⏳ Waiting 15 seconds for volume detachment..."
        sleep 15
    fi
    
    # Scale down deployment to avoid Multi-Attach errors during update
    echo "📉 Scaling down existing deployment to avoid Multi-Attach errors..."
    kubectl -n postgres scale deployment postgres-deployment --replicas=0
    
    # Wait for pods to terminate
    echo "⏳ Waiting for pods to terminate (max 60s)..."
    kubectl -n postgres wait --for=delete pod -l app=postgres --timeout=60s 2>/dev/null || true
    
    # Additional wait to ensure volume is fully detached
    echo "⏳ Waiting 10 seconds for volume detachment..."
    sleep 10
fi

# Apply Kubernetes resources
echo "🚀 Applying PostgreSQL resources..."
kubectl apply -f postgres-resources.yaml

# Wait for deployment to be ready
echo "⏳ Waiting for PostgreSQL deployment to be ready (timeout: 5m)..."
if kubectl -n postgres rollout status deployment/postgres-deployment --timeout=5m 2>&1; then
    echo "✅ PostgreSQL deployment successful!"
    
    # Display deployment info
    echo ""
    echo "📊 Deployment Status:"
    kubectl -n postgres get deployment,pod,svc,pvc -o wide
    
    echo ""
    echo "💡 Useful commands:"
    echo "   - Port forward: kubectl port-forward --namespace=postgres deployment/postgres-deployment 54322:5432"
    echo "   - View logs: kubectl -n postgres logs -l app=postgres -f"
    echo "   - Check PVC: kubectl -n postgres describe pvc postgres-pvc"
    echo "   - Check events: kubectl -n postgres get events --sort-by='.lastTimestamp'"
    echo "   - Connect: psql -h localhost -p 54322 -U postgres"
else
    echo "❌ PostgreSQL deployment failed or timed out"
    echo ""
    echo "🔍 Troubleshooting steps:"
    
    # Check for Multi-Attach errors
    if kubectl -n postgres get events 2>/dev/null | grep -i "multi-attach\|FailedAttachVolume\|already.*used" >/dev/null; then
        echo "⚠️  Multi-Attach error detected!"
        echo "   This occurs when a volume is still attached to another pod."
        echo ""
        echo "   To resolve:"
        echo "   1. Force cleanup: kubectl -n postgres delete pods -l app=postgres --force --grace-period=0"
        echo "   2. Wait 30 seconds for volume detachment"
        echo "   3. Re-run this script"
        echo ""
        echo "   Or use manual cleanup:"
        echo "   kubectl -n postgres delete deployment postgres-deployment"
        echo "   kubectl -n postgres delete pvc postgres-pvc"
        echo "   Then re-apply the resources"
    fi
    
    echo ""
    echo "   - View pod events: kubectl -n postgres get events --sort-by='.lastTimestamp'"
    echo "   - View pod logs: kubectl -n postgres logs -l app=postgres"
    echo "   - Describe pods: kubectl -n postgres describe pods -l app=postgres"
    echo "   - Check PVC status: kubectl -n postgres describe pvc postgres-pvc"
    
    exit 1
fi

# ==========================================
# 🛡️  SECURE COROOT INTEGRATION
# ==========================================
echo ""
echo "🔍 Checking for Coroot Observability..."

if kubectl get ns coroot >/dev/null 2>&1; then
    echo "✅ Coroot namespace detected. Configuring secure integration..."
    
    
    # Credentials passed via Env Var from deploy_components.sh (Local CredStore)
    COROOT_USER="coroot"
    
    
    if [ -n "${COROOT_PG_PASSWORD:-}" ]; then
        echo "🔐 Using secure credential provided by deployment environment."
        COROOT_PASS="$COROOT_PG_PASSWORD"
    else
        echo "❌ COROOT_PG_PASSWORD not set in environment. Skipping secure integration."
        exit 0
    fi
    
    # 2. Create/Update Kubernetes Secret
    echo "📦 Syncing Kubernetes Secret (postgres-coroot-creds)..."
    kubectl create secret generic postgres-coroot-creds \
        --namespace postgres \
        --from-literal=username="$COROOT_USER" \
        --from-literal=password="$COROOT_PASS" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # 3. Configure Postgres User & Extension (Idempotent)
    echo "🐘 Configuring Postgres Roles & Extensions..."
    
    # Get a running pod
    POD=$(kubectl get pod -n postgres -l app=postgres -o jsonpath="{.items[0].metadata.name}")
    
    # SQL: Create user if not exists, update password, grant monitor, create extension
    SQL_COMMANDS="
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$COROOT_USER') THEN
        CREATE USER $COROOT_USER WITH LOGIN PASSWORD '$COROOT_PASS';
      ELSE
        ALTER USER $COROOT_USER WITH PASSWORD '$COROOT_PASS';
      END IF;
      
      GRANT pg_monitor TO $COROOT_USER;
      CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    END
    \$\$;
    "
    
    if kubectl exec -n postgres "$POD" -- psql -U postgres -c "$SQL_COMMANDS"; then
        echo "✅ Postgres user '$COROOT_USER' and extension 'pg_stat_statements' configured."
    else
        echo "❌ Failed to execute SQL commands."
    fi
    
    # 4. Annotate Deployment for Coroot Agent
    echo "🏷️  Annotating Deployment for Coroot Agent..."
    kubectl patch deployment postgres-deployment -n postgres --type='merge' -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"coroot.com/postgres-scrape\":\"true\",\"coroot.com/postgres-scrape-credentials-secret-name\":\"postgres-coroot-creds\",\"coroot.com/postgres-scrape-credentials-secret-username-key\":\"username\",\"coroot.com/postgres-scrape-credentials-secret-password-key\":\"password\"}}}}}"
    
    echo "✅ Integration Complete! Coroot will begin collecting metrics shortly."

else
    echo "ℹ️  Coroot namespace not found. Skipping integration."
fi