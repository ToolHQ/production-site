# Task: Interactive FinOps Reports (Kubecost TUI)

**Status**: [X] Done
**Priority**: High
**Effort**: Medium
**Description**: 
Implement an interactive FinOps dashboard within the TUI to visualize Kubecost data, offering actionable insights for cost reduction (Right-Sizing) and waste management (Abandoned Workloads).

## Delivered Features
- [x] **Kubecost TUI View**: Integrated `kubecost_view.sh` into the main menu.
- [x] **Right-Sizing Recommendations**: Fetches CPU/RAM recommendations from Kubecost API and displays them in a table.
- [x] **Abandoned Workload Detection**: Identifies pods with low usage (<5% CPU/RAM) over 7 days.
- [x] **Safe Mode Suspension**: Allows "Suspending" (scaling to 0) unused deployments with a single keypress, with automatic backup/annotation for restoration.

## Technical Implementation
- Script: `scripts/finops/kubecost_view.sh`
- API Interaction: Queries Kubecost `/model/allocation` and `/model/savings` endpoints.
- UI: Uses `gum` for interactive tables and confirmation dialogs.

## Verification
- Verified "Right-Sizing" displays correct recommendations (e.g. reduce Request from 100m to 10m).
- Succesfully suspended test workload and verified scale-down.
