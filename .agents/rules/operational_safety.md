---
description: "Strict rules for operational safety and protecting critical resources."
globs: "**/*"
---

# Operational Safety Rules

**CRITICAL DIRECTIVE**: You are strictly FORBIDDEN from deleting critical or stateful resources without explicit user confirmation via `notify_user`.

## Protected Resources
The following Kubernetes resources are considered "Protected" and must NEVER be deleted automatically:
1.  **StatefulSets** (e.g., Elasticsearch, Postgres, ClickHouse, Nexus).
2.  **Deployments** for major applications (e.g., Kibana, Cert-Manager, Ingress Controllers).
3.  **PersistentVolumeClaims (PVCs)** and **PersistentVolumes (PVs)**.
4.  **CustomResourceDefinitions (CRDs)** related to infrastructure.
5.  **Namespaces** (except ephemeral test namespaces created by you).

## Mandatory Confirmation Protocol
Before taking any destructive action on a Protected Resource:
1.  **STOP**. Do not proceed with the deletion command.
2.  **Assess Impact**. Determine if data will be lost or service interrupted.
3.  **Ask Permission**. You MUST call `notify_user` with a clear warning:
    > "I need to delete the [RESOURCE_NAME] to [REASON]. This action is irreversible for the workload configuration (though data in PVCs may persist). Do you approve?"

## Authorized Exceptions
You may proceed without confirmation ONLY for:
-   Restarting specific Pods (e.g., `kubectl delete pod`).
-   Scaling Deployments *up* or *down* temporarily (provided no data loss occurs).
-   Deleting failed Jobs or completed Pods.
-   Deleting ephemeral test resources explicitly created during the current task.

**IF IN DOUBT, ASK FIRST.** It is better to annoy the user with a question than to destroy their environment.
