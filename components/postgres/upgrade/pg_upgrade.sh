#!/bin/bash

# Define directories
PGDATA16="/var/lib/postgresql/16/data"
PGDATA17="/var/lib/postgresql/17/data"

# Ensure directories exist and have the right permissions
mkdir -p $PGDATA16 $PGDATA17
chown -R postgres:postgres /var/lib/postgresql

# Stop PostgreSQL if running
pg_ctl -D $PGDATA16 stop || true

# Run pg_upgrade
pg_upgrade -b /usr/local/pgsql16/bin -B /usr/local/pgsql17/bin -d $PGDATA16 -D $PGDATA17

# Move the upgraded data directory to the expected location
mv $PGDATA17 /var/lib/postgresql/data

# Start PostgreSQL 17
pg_ctl -D /var/lib/postgresql/data start
