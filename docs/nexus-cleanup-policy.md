# Nexus Cleanup Policy Automation

Date: 2026-04-19

## Why this exists

The MinIO bucket `nexus/` is live Nexus blob-store storage, not backup backlog. That means retention must be handled from Nexus itself.

Live audit on 2026-04-19 established:

- `docker-repo`, `npm-repo`, `npm-proxy`, and `npm-group` all currently have `cleanup: null`.
- The built-in Nexus tasks `repository.cleanup` and `assetBlob.cleanup` already exist.
- No compact blob store task was observed in the task inventory used during the audit.
- The live public REST API supports attaching existing cleanup policies to repositories through `cleanup.policyNames` on repository `PUT` payloads.
- The live public REST API does not expose cleanup-policy creation or task creation endpoints in Swagger.
- The live Script API is enabled, so full automation remains possible once a vetted Groovy script is committed.

## Safe policy boundary

Current safe stance:

1. `npm-proxy` is the first valid target for cleanup policies because it is cache data backed by the public npm registry.
2. `docker-repo` stays conservative for now; internal container images are rollback material.
3. `npm-repo` stays conservative for now; internal package versions are rollback material.
4. `npm-group` stays conservative; it is an aggregation endpoint, not the place to start retention.
5. No MinIO-side lifecycle, `mc rm`, or raw bucket deletion should be used for Nexus cleanup.

## Repo-side automation available now

The following helpers were added to `oci-k8s-cluster/lib/nexus_init.sh`:

- `nexus_show_cleanup_status`
- `nexus_get_repository_json`
- `nexus_set_repository_cleanup_policies`
- `nexus_clear_repository_cleanup_policies`
- `nexus_set_npm_proxy_cleanup_policies`
- `nexus_set_npm_hosted_cleanup_policies`
- `nexus_set_docker_hosted_cleanup_policies`

These helpers can audit cleanup attachment and attach policy names that already exist in Nexus.
They do not create cleanup policies yet.

## Example usage

With a Nexus tunnel or port-forward active:

```bash
source oci-k8s-cluster/lib/nexus_init.sh
export NEXUS_API_BASE=http://localhost:8081

# Audit current repository cleanup attachment and cleanup-related tasks
nexus_show_cleanup_status

# Attach an already-existing cleanup policy to npm-proxy
nexus_set_npm_proxy_cleanup_policies npm-proxy npm-proxy-unused-30d

# Clear cleanup attachment again if needed
nexus_clear_repository_cleanup_policies npm proxy npm-proxy
```

## Recommended first live policy

The first live policy should target only `npm-proxy` and should be created in Nexus before attachment.

Recommended characteristics:

- format: `npm`
- scope: proxy cache only
- criterion: component usage age, not MinIO object age
- goal: remove npm packages not used recently enough to justify local cache residency

Suggested initial name:

- `npm-proxy-unused-30d`

This name is intentionally descriptive and keeps room for future variants like `45d` or `90d`.

## What still remains open

1. Commit a vetted Groovy script that creates cleanup policies through Script API.
2. Decide whether the blob store `minio` also needs a compact-blob-store task after soft deletes begin.
3. Apply the first live policy to `npm-proxy` and validate soft-delete plus blob cleanup behavior.

## References

- `docs/backup-policy.md`
- `oci-k8s-cluster/lib/nexus_init.sh`
- `tasks/2026/Q2/T-132-Nexus-Cleanup-Policy-Automation.md`
