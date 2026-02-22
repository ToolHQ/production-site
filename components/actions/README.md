# Global App Limits
**Managed by:** `commands.sh` (T-100 Zero-Waste Lockdown)

## Overview
This "Action" component applies standard LimitRanges to application namespaces to ensure NO pod is ever created without resource limits ("Gatekeeper" function).

## Configuration Files
- **`app-limit-range.yaml`**:
    - **Default Request**: 50m CPU / 64Mi Memory
    - **Default Limit**: 200m CPU / 256Mi Memory
- **`commands.sh`**: applies this YAML to the following namespaces:
    - `default`
    - `nexus`
    - `postgres`

## Usage
Deploy this component via `deploy_components.sh` to refresh/enforce policies across the cluster.
