# T-033: Windows Loopback Bridge for WSL Tunnels

**Status**: In Progress
**Priority**: High
**Owner**: DevExp (TUI)
**Est. Effort**: 2h

## Context
When running the TUI inside WSL 2, Kubernetes port-forwards bind to the WSL network interface. By default, these are not accessible from Windows on `localhost` or typical loopback addresses like `127.0.0.2` without specific networking bridges.
The user requires maintaining standard PostgreSQL ports (`5432`) but using distinct Loopback IPs (`127.0.0.2` for Primary, `127.0.0.3` for Replica) to differentiate services on the Windows host.

## Objective
Implement a "Double Bridge" mechanism in `k8s_ops_menu.sh` that allows Windows applications (DBeaver, PowerBI) to connect to `127.0.0.2:5432` (Windows side) and have that traffic transparently routed to the Kubernetes Pod inside WSL->Cluster.

## Technical Implementation Plan

### Architecture: Double Bridge
1.  **Level 1 (Linux Tunnel)**: `ssh -L` creates a tunnel from `127.0.0.X:5432` (WSL) to the K8s Node IP (`10.0.X.X:5432`).
2.  **Level 2 (WSL Bridge)**: `socat` exposes the WSL Loopback (`127.0.0.X:5432`) to the WSL Interface (`0.0.0.0` or `ETH0_IP`) on a high random port (e.g., `15432`).
3.  **Level 3 (Windows Proxy)**: A PowerShell script, generated and executed by the TUI, runs on Windows. It creates a `System.Net.Sockets.TcpListener` on `127.0.0.X:5432` (Windows) and forwards traffic to `WSL_IP:15432`.

### Changes Required

#### `oci-k8s-cluster/k8s_ops_menu.sh`
-   **Modify**: `start_tunnel` function.
-   **New Logic**:
    -   Check for WSL environment.
    -   If standard loopback (`127.0.0.1`), use normal behavior.
    -   If custom loopback (`127.0.0.2+`):
        -   Spawn `socat` bridge in background.
        -   Generate ephemeral PowerShell script.
        -   Execute PowerShell script using `powershell.exe -ExecutionPolicy Bypass`.
        -   Ensure cleanup of both `socat` and PowerShell process on exit.

## Verification
-   [ ] Verify `start_tunnel` launches `socat`.
-   [ ] Verify `powershell.exe` process is running.
-   [ ] `netstat -an` on Windows shows listening on `127.0.0.2:5432`.
-   [ ] DBeaver connection to `127.0.0.2:5432` succeeds.
