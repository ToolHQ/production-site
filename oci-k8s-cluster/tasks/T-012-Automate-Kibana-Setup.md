# Task T-012: Automate Kibana Data View Creation

**Status**: ✅ Done
**Epic**: Observability
**Estimate**: 2 hours

## Description
Eliminate the manual step of configuring "Data Views" (Index Patterns) in Kibana. The system should automatically configure a default Data View for `logs-*` upon deployment.

## Directives
1.  **Scripted Setup**: Create a script (or Kubernetes Job) that interacts with the Kibana API.
2.  **Idempotency**: The script must check if the view exists before attempting creation.
3.  **Authentication**: Use the existing `elastic` user credentials securely (from Secrets).
4.  **Integration**: Add this step to `components/observability/commands.sh` or a post-install hook.

## Technical Details
- **API Endpoint**: `/api/data_views/data_view` (Kibana > 8.0)
- **Target Pattern**: `logs-*`
- **Timestamp Field**: `app@timestamp`

## Goal
Running the `observability` component setup fully prepares Kibana for immediate log analysis without user interaction.
