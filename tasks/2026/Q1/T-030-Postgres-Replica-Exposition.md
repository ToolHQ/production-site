# T-030: Postgres Replica Exposition

## Objective
Expose PostgreSQL replicas (Primary and Read-Only) via SSH tunnels bound to specific Loopback Aliases (127.0.0.2, 127.0.0.3, etc.) and map them to friendly DNS names (`postgres.dnor.io`, `postgres-ro.dnor.io`) in `/etc/hosts`.

## Context
Currently, we expose services via `localhost:PORT`. However, for a replicated database, we want to simulate a production-like environment where:
- `postgres.dnor.io` -> Primary (Writes)
- `postgres-ro.dnor.io` -> Read-Only Replica (Reads)

By binding SSH tunnels to distinct loopback IPs (e.g., `127.0.0.2`), we can map these domains in `/etc/hosts` to the respective loopback IPs. This allows tools (DBeaver, Applications) to connect to "domains" rather than distinct ports on localhost, and keeps standard ports (5432) available on those specific IPs.

## Requirements

### 1. Loopback Binding in Tunnels
- Update `k8s_ops_menu.sh` (or create a specific Postgres TUI submodule) to support binding SSH tunnels to specific IPs (not just 127.0.0.1).
- **Primary (`postgres-0`)**: Bind to `127.0.0.2:5432`.
- **Standby (`postgres-1`)**: Bind to `127.0.0.3:5432`.

### 2. DNS/Hosts Management
- Create/Update a script (e.g., `scripts/maintenance/map_postgres_hosts.sh`) to automatically update `/etc/hosts` (and Windows hosts file via WSL interop if possible, or print instructions).
- Map `127.0.0.2` -> `postgres.dnor.io`.
- Map `127.0.0.3` -> `postgres-ro.dnor.io`.

### 3. Scalability
- The solution should be "smart" enough to handle future replicas (e.g., `postgres-2` -> `127.0.0.4` -> `postgres-ro-2.dnor.io`).

## Acceptance Criteria
- [ ] TUI Option "Expose Postgres Cluster" which sets up:
    - Tunnel `127.0.0.2:5432` -> `postgres-0:5432`
    - Tunnel `127.0.0.3:5432` -> `postgres-1:5432`
- [ ] Script to verify/update `/etc/hosts` with these mappings.
- [ ] Verification: `psql -h postgres.dnor.io` connects to Primary.
- [ ] Verification: `psql -h postgres-ro.dnor.io` connects to Standby.
