# Task T-025: Implement Robust Coroot Observability

**Status**: ✅ Done
**Epic**: Observability
**Estimate**: 4 hours
**Owner**: Obs.

## Description
Enhance the Coroot installation script (`scripts/observability/install_coroot.sh`) to support "Upsert" (Idempotency), automatic Cloud Cost configuration for OCI, and zero-touch Postgres integration.

## Requirements

1.  **Upsert Capability**:
    -   Script must detect existing namespace/resources.
    -   Update existing deployment (Helm Upgrade) without data loss.
    -   Handle passwordless authentication persistence.

2.  **OCI Cloud Integration**:
    -   Detect OCI Environment via Metadata Service.
    -   Identify instance shape (`VM.Standard.A1.Flex`).
    -   Output precise pricing configuration for Coroot Cost settings.

3.  **Postgres Autodiscovery**:
    -   Scan cluster for `postgres-deployment`.
    -   Detect credentials from Secrets.
    -   Apply `coroot.com/postgres-scrape` annotations automatically.

## Implementation Details

-   **Script**: `scripts/observability/install_coroot.sh`
-   **Method**:
    -   Used `kubectl set env` for password removal (robustness).
    -   Used `curl` to IMDS (169.254.169.254) for detection.
    -   Used `kubectl patch` for Postgres integration.

## Verification
-   [x] Script runs idempotently (updates without error).
-   [x] OCI Shape is detected and pricing displayed.
-   [x] Postgres deployment receives annotations.
