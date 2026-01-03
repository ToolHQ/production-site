#!/bin/bash
set -e

# Detect Mode based on POD_NAME (preferred for HostNetwork) or Hostname
if [ -n "$POD_NAME" ]; then
    IDENTITY="$POD_NAME"
else
    IDENTITY=$(hostname)
fi

echo "🐘 Postgres Entrypoint Wrapper - Identity: $IDENTITY"

if [[ "$IDENTITY" =~ -0$ ]]; then
    ROLE="primary"
    echo "👑 Detected Role: PRIMARY"
    PGdata=${PGDATA:-/var/lib/postgresql/data}
    if [ -f "$PGdata/standby.signal" ]; then
        echo "⚠️  Found stale standby.signal on Primary. Removing it..."
        rm -f "$PGdata/standby.signal"
    fi
else
    ROLE="standby"
    echo "🛡️ Detected Role: STANDBY"
fi

# Function to configure Primary
configure_primary() {
    echo "🔧 Configuring Primary..."
    # Background job to Create Replicator User & Configure pg_hba.conf
    (
        sleep 5
        echo "⏳ Waiting for Postgres to start to configure replication user..."
        until pg_isready -U postgres -d template1; do sleep 2; done
        
        echo "👤 Checking 'replicator' user..."
        if [ -z "$POSTGRES_REPLICATION_PASSWORD" ]; then
             echo "❌ POSTGRES_REPLICATION_PASSWORD not set!"
             exit 1
        fi
        
        # Idempotent User Creation using Shell Logic (No PL/pgSQL needed)
        # Ensure PL/pgSQL exists (Standard extension)
        psql -U postgres -d template1 -c "CREATE EXTENSION IF NOT EXISTS plpgsql;"
        
        USER_EXISTS=$(psql -U postgres -d template1 -tAc "SELECT 1 FROM pg_roles WHERE rolname='replicator'")
        
        if [ "$USER_EXISTS" == "1" ]; then
            echo "🔄 User 'replicator' exists. Updating password..."
            psql -U postgres -d template1 -c "ALTER USER replicator WITH PASSWORD '$POSTGRES_REPLICATION_PASSWORD';"
        else
            echo "🆕 Creating user 'replicator'..."
            psql -U postgres -d template1 -c "CREATE USER replicator WITH REPLICATION LOGIN ENCRYPTED PASSWORD '$POSTGRES_REPLICATION_PASSWORD';"
        fi
        
        # Configure pg_hba.conf
        echo "📄 Configuring pg_hba.conf for replication..."
        PGdata=${PGDATA:-/var/lib/postgresql/data}
        if ! grep -q "replicator" "$PGdata/pg_hba.conf"; then
            echo "host replication replicator 0.0.0.0/0 md5" >> "$PGdata/pg_hba.conf"
            # Ensure general external access (Fix for user connectivity)
            echo "host all all 0.0.0.0/0 md5" >> "$PGdata/pg_hba.conf"
            
            psql -U postgres -d template1 -c "SELECT pg_reload_conf();"
            echo "✅ pg_hba.conf updated."
        fi
    ) &
}

# Function to configure Standby
configure_standby() {
    echo "🔧 Configuring Standby..."
    PGdata=${PGDATA:-/var/lib/postgresql/data}
    
    # Check if PG_VERSION exists
    if [ ! -f "$PGdata/PG_VERSION" ]; then
        echo "📂 No PG_VERSION found. Cloning from Primary..."
        
        # Ensure directory is empty
        if [[ "$PGdata" == *"/pgdata" ]]; then
            echo "🧹 Cleaning target directory $PGdata..."
            rm -rf "$PGdata"/*
            rm -rf "$PGdata"/.* 2>/dev/null || true
        fi
        
        # Wait for Primary
        until PGPASSWORD=$POSTGRES_REPLICATION_PASSWORD psql -h postgres-0.postgres-internal -U replicator -d template1 -c '\l' >/dev/null 2>&1; do
            echo "⏳ Waiting for Primary (postgres-0) to be ready..."
            sleep 5
        done
        
        echo "🚀 Starting Base Backup..."
        PGPASSWORD=$POSTGRES_REPLICATION_PASSWORD pg_basebackup \
            -h postgres-0.postgres-internal \
            -U replicator \
            -D "$PGdata" \
            -Fp -Xs -P -R
            
        echo "✅ Backup complete. Fixing permissions..."
        chown -R postgres:postgres "$PGdata"
        chmod 700 "$PGdata"
    else
        echo "📂 PG_VERSION found. Assuming existing standby data."
        if [ ! -f "$PGdata/standby.signal" ]; then
             echo "⚠️  standby.signal missing! Creating it to enforce Standby mode."
             touch "$PGdata/standby.signal"
        fi
    fi
}

# Main Execution Logic
if [ "$ROLE" == "primary" ]; then
    configure_primary
else
    configure_standby
fi

# Exec standard entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
