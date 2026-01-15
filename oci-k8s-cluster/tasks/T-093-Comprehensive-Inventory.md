# T-093: Comprehensive Storage Inventory & PDF Report

## Context
The user requires a "decision-making" level report on the cluster's storage state. This includes:
-   **Kubernetes (PV/PVC)**: What is allocated vs used.
-   **Minio (Object Storage)**: What is stored in buckets vs phantom files.
-   **Google Drive (Cloud)**: Verification of offsite backup content.
-   **Orphans**: Manual backups or untracked archives consuming space.

## Requirements
1.  **Multi-Format Output**:
    -   **Terminal**: Standard ANSI output for TUI.
    -   **HTML**: For rich viewing and PDF export.
    -   **Markdown**: For documentation.
2.  **Performance Optimization**:
    -   The current reporting is too slow (~minutes).
    -   **Solution**: Parallelize Node Scanning (SSH) and optimize `du` commands.
3.  **Completeness**:
    -   Must align "What is in K8s" vs "What is on Disk" vs "What is in Cloud".

## Implementation Plan
### Phase 1: Performance (The Executor)
-   Refactor `generate_storage_dossier.sh` (or create new `generate_inventory.sh`) to use `&` backgrounding for SSH calls.
-   Use `wait` to gather results.
-   Write temp files per node (`/tmp/node-X.stats`).

### Phase 2: Data Gathering
-   **K8s**: `kubectl get pv,pvc`
-   **Minio**: `mc` or `du /data/minio` (Host path analysis).
-   **GDrive**: `rclone lsjson` for fast parsing.
-   **Local**: `find / -name "*.tar.gz"` (smart scan).

### Phase 3: Formatting
-   Create a Jinja2-like (using `sed`/`awk`) template for HTML.
-   Generate Markdown table.
-   Output ANSI to STDOUT.

## Timeline
-   **Status**: Planning / In Progress
-   **Owner**: Antigravity
