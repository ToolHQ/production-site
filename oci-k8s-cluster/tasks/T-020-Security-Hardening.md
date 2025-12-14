# T-020: Security Hardening (SSH & Audit)
**Status**: In Progress
**Priority**: High
**Owner**: Sec

## Context
The recent Cluster Technical Audit (`cluster_scorecard.md`) identified significant security gaps, specifically "Permissive SSH" (`StrictHostKeyChecking=no`) and "No Audit Trail" for TUI actions.
Currently, automation scripts prioritize convenience over security by disabling host key verification, making the cluster vulnerable to MITM attacks. Additionally, powerful TUI actions (Node Reset, Volume Delete) leave no trace.

## Objectives
1.  **SSH Hardening**: 
    - Enable `StrictHostKeyChecking` where feasible.
    - Implement proper `known_hosts` management or robust Key Rotation.
2.  **Audit Logging**: 
    - Instrument `k8s_ops_menu.sh` and sub-scripts to log all modifying actions (Who, What, When) to `/var/log/k8s_ops.log`.
    - Create a "View Audit Log" TUI option.

## Implementation Plan

### 1. Audit Logging (Low Risk, High Value)
- [ ] Create `lib/audit.sh` library:
    - `log_action "CATEGORY" "Message"` function.
- [ ] Integrate into `common.sh` or `k8s_ops_menu.sh`.
- [ ] Wrap critical actions (Delete, Resize, Cordon, Drain) with `log_action`.
- [ ] Create TUI viewer (Option 14 -> View Audit Logs).

### 2. SSH Hardening (Medium Risk)
- [ ] **Audit Current Usage**: Find all `ssh` calls with `-o StrictHostKeyChecking=no`.
- [ ] **Strategy**:
    - **Step 1**: Pre-scan host keys. Create a helper `scan_known_hosts.sh` that populates `~/.ssh/known_hosts` for all cluster nodes.
    - **Step 2**: Update `common.sh` to use verify-host-key mode, falling back to "Scan & Retry" if key changed (with warning).
    - **Step 3**: Rotate Keys (Optional/Advanced).

## Validation
- **Audit**: Run a destructive action (e.g., Cordon Node) -> Check `/var/log/k8s_ops.log` -> Verify entry exists.
- **SSH**: Verify `ssh` commands no longer use `StrictHostKeyChecking=no` (or verify `known_hosts` is populated).
