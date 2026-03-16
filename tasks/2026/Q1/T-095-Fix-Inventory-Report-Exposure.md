# T-095: Fix Inventory Report Exposure

- **Status**:   Done
- **Priority**: 🚨 Critical
- **Epic/Owner**: Ops
- **Estimation**: 2h

## Context
The inventory report was served via an unmanaged local Python server that frequently died or became inaccessible. This task moved the server management to a robust TUI-integrated helper.

## Tasks
- [x] Investigate `generate_inventory_report.sh` server logic
- [x] Confirm local port 8000 state and process health
- [x] Design local TUI-integrated server helper (`report_server.sh`)
- [x] Implement `report_server.sh` with PID tracking (start/stop/status/restart)
- [x] Integrate `report_server.sh` call into `generate_inventory_report.sh`
- [x] Create `systemd` user service template for optional persistence
- [x] Verify server lifecycle and access at `http://localhost:8000/inventory.html`
