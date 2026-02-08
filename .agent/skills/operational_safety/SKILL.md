---
description: "Protocols for safe cluster operations and critical resource protection."
---

# Operational Safety Protocols

**CRITICAL RULE**: You (the Agent) are strictly FORBIDDEN from deleting critical or stateful resources without explicit user confirmation via `notify_user`.

## Protected Resources
The following Kubernetes resources are considered "Protected" and must NEVER be deleted automatically:
1.  **StatefulSets** (e.g., Elasticsearch, Postgres, ClickHouse, Nexus).
2.  **Deployments** for major applications (e.g., Kibana, Cert-Manager, Ingress Controllers).
3.  **PersistentVolumeClaims (PVCs)** and **PersistentVolumes (PVs)**.
4.  **CustomResourceDefinitions (CRDs)** related to infrastructure (e.g., ECK, Longhorn).
5.  **Namespaces** (except ephemeral test namespaces created by you).

## Authorized Actions (Without Confirmation)
You may proceed without confirmation ONLY for:
-   Restarting specific Pods (e.g., `kubectl delete pod`) to trigger a restart.
-   Scaling Deployments *up* or *down* temporarily (provided no data loss occurs).
-   Deleting failed Jobs or completed Pods.
-   Deleting ephemeral test resources you explicitly created during the current task.

## Mandatory Workflow for Destructive Actions
If a task requires deleting a Protected Resource (e.g., to free up CPU or remove legacy apps):
1.  **Impact Analysis**: Check for dependencies and data persistence (PVCs).
2.  **Propose Plan**: Create an `implementation_plan.md` detailing exactly what will be deleted.
3.  **Ask Permission**: Call `notify_user` with a clear warning:
    > "I need to delete the [RESOURCE_NAME] to [REASON]. This action is irreversible for the workload configuration (though data in PVCs may persist). Do you approve?"

## Recovery Protocols
If a critical resource is accidentally deleted or needs executing:
1.  **Verify Data Safety**: Check `kubectl get pvc` immediately.
2.  **Restore Configuration**: Redeploy using existing manifests in `components/`.
3.  **Notify User**: Inform the user of the action and the restoration status.
