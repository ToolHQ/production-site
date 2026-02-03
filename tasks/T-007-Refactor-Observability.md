# Task T-007: Refactor Observability to Components

**Status**: ✅ Done
**Epic**: Refactoring
**Estimate**: 1 hour

## Description
Move the ad-hoc `manifests/logging` and `setup_observability.sh` into the standard `components/` structure to be compatible with TUI Option 5 ("Component Management").

## Requirements
1.  Create `../components/observability`.
2.  Migrate manifests (`elasticsearch.yaml`, `ingress.yaml`).
3.  Migrate `setup_observability.sh` logic to `commands.sh`.
4.  Verify deployment via `deploy_components.sh` dry-run or verification.

## Architecture
```
components/
└── observability/
    ├── elasticsearch.yaml
    ├── ingress.yaml
    └── commands.sh (Installs Operator & Pixie CLI)
```
