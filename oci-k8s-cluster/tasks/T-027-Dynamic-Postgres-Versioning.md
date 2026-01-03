# Task T-027: Dynamic Postgres Versioning

**Status**: ✅ Done
**Epic**: Infrastructure / Maintainability
**Estimate**: 1 hour
**Owner**: Infra

## Description
Eliminate hardcoded version numbers in deployment scripts (`postgres:18.0-alpine3.22`) by implementing robust parsing of the `Dockerfile` source of truth. This allows seamless upgrades by simply modifying the Dockerfile.

## Requirements

1.  **Single Source of Truth**:
    -   The `Dockerfile` `FROM` instruction determines the version.
    -   Scripts must extract this version dynamically.

2.  **Tag Consistency**:
    -   Generated Docker tags must reflect the version + git hash.
    -   Example: `postgres:18.1-alpine3.22-d51edeb`.

3.  **Manifest Injection**:
    -   `postgres-resources.yaml` must be updated on-the-fly (`sed`) to match the built image tag.

## Implementation Details

-   **Script**: `components/postgres/build.sh`
-   **Logic**:
    ```bash
    # Extract version from Dockerfile
    VERSION=$(grep "FROM" Dockerfile | awk '{print $2}' | cut -d: -f2)
    # Generate Tag
    TAG="${VERSION}-${HASH}"
    ```
-   **Reasoning**:
    -   Prevents "Drift" where script installs `v18` but Dockerfile builds `v19`.
    -   Simplifies upgrades: `sed -i 's/18.0/19.0/' Dockerfile` -> Deploy -> Done.

## Verification
-   [x] Changing Dockerfile version updates the deployment.
-   [x] Image tag in `kubectl get deployment` matches Dockerfile version.
-   [x] No manual editing of `build.sh` required for version bumps.
