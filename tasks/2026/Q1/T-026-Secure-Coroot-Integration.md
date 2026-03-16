# Task T-026: Secure Coroot Integration for Postgres

**Status**: ✅ Done
**Epic**: Security / Observability
**Estimate**: 2 hours
**Owner**: Infra

## Description
Integrate Coroot Observability with PostgreSQL securely, ensuring no plain-text credentials are ever exposed in scripts, logs, or command history. Implement a robust credential lifecycle using `credstore.sh`.

## Requirements

1.  **Credential Security**:
    -   Generate strict random passwords (OpenSSL) locally.
    -   Store encrypted in `credstore.sh` (User-isolated).
    -   Inject into Kubernetes via Secrets, never arguments.

2.  **Zero-Trust Execution**:
    -   Remote execution must not echo credentials.
    -   Pass secrets via Environment Variables only.
    -   Use `kubectl set env` or secret mounts for Pod access.

3.  **Observability Integration**:
    -   Create `postgres-coroot-creds` secret automatically.
    -   Create `coroot` user with `pg_monitor` role in Postgres.
    -   Annotate Deployment for Coroot Agent discovery.

## Implementation Details

-   **Manager**: `oci-k8s-cluster/deploy_components.sh`
-   **Execution**:
    -   Added `credstore_delete` alias to fix bug.
    -   Fixed JSON parsing in `credstore.sh` to handle empty credentials.
    -   Escaped remote variables (`\$`) vs injected local variables (`$var`).
-   **Architecture**:
    -   Local: `credstore.sh` -> Generates/Stores.
    -   Transport: Env Var Injection -> `ssh`.
    -   Remote: `commands.sh` -> Reads Env -> `kubectl create secret` -> `psql`.

## Verification
-   [x] Password is never shown in stdout/logs.
-   [x] Credential persists in `~/.local/share/k8s_ops/credentials.json`.
-   [x] Remote `commands.sh` successfully configures user and extension.
-   [x] Coroot Dashboard shows Postgres metrics (Connections, CPU, Locks).
